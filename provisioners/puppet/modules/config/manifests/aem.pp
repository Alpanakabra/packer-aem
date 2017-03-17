# == Class: config::aem
#
#  Shared Resources used by other AEM modules
#
# === Parameters
#
# [*tmp_dir*]
#   A temporary directory used for staging
#
# [*aem_role*]
#   The AEM role to install. Should be 'publish' or 'author'.
#
# [*aem_port*]
#   TCP port AEM will listen on.
#
# [*aem_quickstart_source*]
# [*aem_license_source*]
#   URLs (s3://, http:// or file://) for the AEM jar and license files.
#
# [*aem_healthcheck_version*]
#   The version of the AEM healthcheck service to install.
#
# [*aem_base*]
#   Base directory for installing AEM.
#
# [*aem_sample_content*]
#   Boolean that determines whether the AEM sample content should be installed.
#
# [*aem_jvm_mem_opts*]
#   Extra memory options to be passed to the JVM.
#
# [*setup_repository_volume*]
#   Boolean that determines whether a separate volume is formatted and mounted
#   for the AEM repository.
#
# [*repository_volume_device*]
#   The device for format and mount for the AEM repository.
#
# [*repository_volume_mount_point*]
#   The mount point for the AEM repository volume.
#
# [*sleep_secs*]
#   Number of seconds to sleep to allow AEM to settle. If installation fails,
#   try turning this up.
#
# === Authors
#
# Andy Wang <andy.wang@shinesolutions.com>
# James Sinclair <james.sinclair@shinesolutions.com>
#
# === Copyright
#
# Copyright © 2017 Shine Solutions Group, unless otherwise noted.
#

class config::aem (
  $tmp_dir,

  $aem_role,
  $aem_port,
  $aem_quickstart_source,
  $aem_license_source,
  $aem_artifacts_base,
  $aem_healthcheck_version,
  $aem_base           = '/opt',
  $aem_sample_content = false,
  $aem_jvm_mem_opts   = '-Xss4m -Xmx8192m',

  $setup_repository_volume       = false,
  $repository_volume_device      = '/dev/xvdb',
  $repostory_volume_mount_point = '/mnt/ebs1',

  $sleep_secs = 120,
) {

  include ::config::java

  Exec {
    cwd  => '/tmp',
    path => [ '/bin', '/sbin', '/usr/bin', '/usr/sbin' ],
  }

  if $setup_repository_volume {
    exec { 'Prepare device for AEM repository':
      command => "mkfs -t ext4 ${repository_volume_device}",
    } ->
    file { $repository_volume_mount_point:
      ensure => directory,
      mode   => '0755',
    } ->
    mount { $repository_volume_mount_point:
      ensure   => mounted,
      device   => $repository_volume_device,
      fstype   => 'ext4',
      options  => 'nofail,defaults,noatime',
      remounts => false,
      atboot   => false,
    }
  }

  if $::config::base::install_cloudwatchlogs {
    $aem_log_dir = "/opt/aem/${aem_role}/crx-quickstart/logs"
    $aem_apache_datetime_files = [ 'access.log', 'request.log' ]
    $aem_stdout_datetime_files = [ 'stdout.log', 'error.log' ]
    $aem_unknown_datetime_files = [
      # TODO Get example log files to determine `datetime_format`
      'audit.log', 'auditlog.log', 'history.log',
      's7access-2017-03-17.log', 'upgrade.log',
    ]
    $aem_unknown_datetime_files.each |$file| {
      cloudwatchlogs::log { "${aem_log_dir}/${file}":
        notify          => Service['awslogs'],
      }
    }
    $aem_apache_datetime_files.each |$file| {
      cloudwatchlogs::log { "${aem_log_dir}/${file}":
        datetime_format => '%d/%b/%Y:%H:%M:%S %z',
        notify          => Service['awslogs'],
      }
    }
    $aem_stdout_datetime_files.each |$file| {
      cloudwatchlogs::log { "${aem_log_dir}/${file}":
        datetime_format => '%d.%m.%Y %H:%M:%S.%f',
        notify          => Service['awslogs'],
      }
    }
  }

  file { [ "${aem_base}/aem", "${aem_base}/aem/${aem_role}"]:
    ensure => directory,
    mode   => '0775',
    owner  => 'aem',
    group  => 'aem',
  }

  # Retrieve Healthcheck Content Package and move into aem directory
  archive { "${aem_base}/aem/aem-healthcheck-content-${aem_healthcheck_version}.zip":
    ensure  => present,
    source  => "http://central.maven.org/maven2/com/shinesolutions/aem-healthcheck-content/${aem_healthcheck_version}/aem-healthcheck-content-${aem_healthcheck_version}.zip",
    cleanup => false,
    require => File["${aem_base}/aem"],
  } ->
  file { "${aem_base}/aem/aem-healthcheck-content-${aem_healthcheck_version}.zip":
    ensure => file,
    mode   => '0664',
  }

  # Retrieve the cq-quickstart jar
  archive { "${aem_base}/aem/${aem_role}/aem-${aem_role}-${aem_port}.jar":
    ensure  => present,
    source  => $aem_quickstart_source,
    cleanup => false,
    require => File["${aem_base}/aem/${aem_role}"],
  } ->
  file { "${aem_base}/aem/${aem_role}/aem-${aem_role}-${aem_port}.jar":
    ensure  => file,
    mode    => '0775',
    owner   => 'aem',
    group   => 'aem',
    require => File["${aem_base}/aem/${aem_role}"],
  }

  # Set up configuration file for puppet-aem-resources.
  file { '/etc/puppetlabs/puppet/aem.yaml':
    ensure  => file,
    content => epp('config/aem.yaml.epp', { 'port' => $aem_port }),
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
  }

  # Retrieve the license file
  archive { "${aem_base}/aem/${aem_role}/license.properties":
    ensure  => present,
    source  => $aem_license_source,
    cleanup => false,
    require => File["${aem_base}/aem/${aem_role}"],
  } ->
  file { "${aem_base}/aem/${aem_role}/license.properties":
    ensure => file,
    mode   => '0440',
    owner  => 'aem',
    group  => 'aem',
  }

  $jvm_opts = [
    '-XX:+PrintGCDetails',
    '-XX:+PrintGCTimeStamps',
    '-XX:+PrintGCDateStamps',
    '-XX:+PrintTenuringDistribution',
    '-XX:+PrintGCApplicationStoppedTime',
    '-XX:+HeapDumpOnOutOfMemoryError',
  ]

  $sleep_exec = 'Wait until login page is ready post Service Pack 1 Cumulative Fix Pack 1 install'
  aem::instance { 'aem':
    source         => "${aem_base}/aem/${aem_role}/aem-${aem_role}-${aem_port}.jar",
    home           => "${aem_base}/aem/${aem_role}",
    type           => $aem_role,
    port           => $aem_port,
    sample_content => $aem_sample_content,
    jvm_mem_opts   => $aem_jvm_mem_opts,
    jvm_opts       => $jvm_opts.join(' '),
    status         => 'running',
  } ->
  # Confirm AEM Starts up and the login page is ready.
  aem_aem { 'Wait until login page is ready':
    ensure  => login_page_is_ready,
    require => [Aem::Instance['aem'], File['/etc/puppetlabs/puppet/aem.yaml']],
  } ->
  exec { 'Manual delay to let AEM become ready':
    command => "sleep ${sleep_secs}",
  } ->
  # Install AEM service pack, hotfix, and feature pack packages.
  archive { "${tmp_dir}/cq-6.2.0-hotfix-11490-1.2.zip":
    ensure  => present,
    source  => "${aem_artifacts_base}/cq-6.2.0-hotfix-11490-1.2.zip",
    cleanup => false,
  } ->
  aem_package { 'Install hotfix 11490':
    ensure    => present,
    name      => 'cq-6.2.0-hotfix-11490',
    group     => 'adobe/cq620/hotfix',
    version   => '1.2',
    path      => "${tmp_dir}",
    replicate => false,
    activate  => false,
    force     => true,
  } ->
  archive { "${tmp_dir}/cq-6.2.0-hotfix-12785-7.0.zip":
    ensure  => present,
    source  => "${aem_artifacts_base}/cq-6.2.0-hotfix-12785-7.0.zip",
    cleanup => false,
  } ->
  aem_package { 'Install hotfix 12785':
    ensure    => present,
    name      => 'cq-6.2.0-hotfix-12785',
    group     => 'adobe/cq620/hotfix',
    version   => '7.0',
    path      => "${tmp_dir}",
    replicate => false,
    activate  => false,
    force     => true,
  } ->
  exec { 'Wait AEM post hotfix 12785 install':
    command => "sleep ${sleep_secs}",
  } ->
  aem_aem { 'Wait until login page is ready post hotfix 12785 install':
    ensure                     => login_page_is_ready,
    retries_max_tries          => 60,
    retries_base_sleep_seconds => 5,
    retries_max_sleep_seconds  => 5,
  } ->
  exec { 'Restart AEM post hotfix 12785 install':
    command => 'service aem-aem restart',
  } ->
  aem_aem { 'Wait until login page is ready post hotfix 12785 restart':
    ensure                     => login_page_is_ready,
    retries_max_tries          => 120,
    retries_base_sleep_seconds => 5,
    retries_max_sleep_seconds  => 5,
  } ->
  #exec { 'Wait AEM post hotfix 12785 restart':
  #  command => "sleep ${sleep_secs}",
  #} ->
  archive { "${tmp_dir}/aem-service-pkg-6.2.SP1.zip":
    ensure  => present,
    source  => "${aem_artifacts_base}/AEM-6.2-Service-Pack-1-6.2.SP1.zip",
    cleanup => false,
  } ->
  aem_package { 'Install Service Pack 1':
    ensure                     => present,
    name                       => 'aem-service-pkg',
    group                      => 'adobe/cq620/servicepack',
    version                    => '6.2.SP1',
    path                       => "${tmp_dir}",
    replicate                  => false,
    activate                   => false,
    force                      => true,
    retries_max_tries          => 120,
    retries_base_sleep_seconds => 10,
    retries_max_sleep_seconds  => 10,
  } ->
  exec { 'Wait AEM post Service Pack 1 install':
    command => "sleep ${sleep_secs}",
  } ->
  aem_aem { 'Wait until login page is ready post Service Pack 1 install':
    ensure                     => login_page_is_ready,
    retries_max_tries          => 60,
    retries_base_sleep_seconds => 5,
    retries_max_sleep_seconds  => 5,
  } ->
  archive { "${tmp_dir}/cq-6.2.0-sp1-cfp-1.0.zip":
    ensure  => present,
    source  => "${aem_artifacts_base}/AEM-6.2-SP1-CFP1-1.0.zip",
    cleanup => false,
  } ->
  aem_package { 'Install Service Pack 1 Cumulative Fix Pack 1':
    ensure                     => present,
    name                       => 'cq-6.2.0-sp1-cfp',
    group                      => 'adobe/cq620/cumulativefixpack',
    version                    => '1.0',
    path                       => "${tmp_dir}",
    replicate                  => false,
    activate                   => false,
    force                      => true,
    retries_max_tries          => 120,
    retries_base_sleep_seconds => 10,
    retries_max_sleep_seconds  => 10,
  } ->
  exec { 'Wait AEM post Service Pack 1 Cumulative Fix Pack 1 install':
    command => "sleep ${sleep_secs}",
  } ->
  aem_aem { 'Wait until login page is ready post Service Pack 1 Cumulative Fix Pack 1 install':
    ensure                     => login_page_is_ready,
    retries_max_tries          => 60,
    retries_base_sleep_seconds => 5,
    retries_max_sleep_seconds  => 5,
  }
  ########## BROUGHT OVER FROM MASTER ##########





  $aem_resource_classes = $aem_role ? {
    'author'  => [ 'create_system_users', 'author_remove_default_agents' ],
    'publish' => [ 'create_system_users' ],
  }

  $aem_resource_classes.each |$cls| {
    class { "::aem_resources::${cls}":
      require => Exec[$sleep_exec],
    }
  }

  aem_package { 'Install AEM Healthcheck Content Package':
    ensure    => present,
    name      => 'aem-healthcheck-content',
    group     => 'shinesolutions',
    version   => $aem_healthcheck_version,
    path      => "${aem_base}/aem",
    replicate => false,
    activate  => false,
    force     => true,
    require   => Exec[$sleep_exec],
  }

  # Ensure login page is still ready after all provisioning steps and before stopping AEM.
  aem_aem { 'Ensure login page is ready':
    ensure                     => login_page_is_ready,
    retries_max_tries          => 30,
    retries_base_sleep_seconds => 5,
    retries_max_sleep_seconds  => 5,
    require                    => [
      Aem_package['Install AEM Healthcheck Content Package'],
    ] + $aem_resource_classes.map |$cls| { Class["::aem_resources::${cls}"] },
  }

  if $setup_repository_volume {
    exec { 'service aem-aem stop':
      require => Exec['Ensure login page is ready'],
    } ->
    exec { "mv ${author::aem_base}/aem/author/crx-quickstart/repository/* ${author::aem_repo_mount_point}/":
    } ->
    file { "${author::aem_base}/aem/author/crx-quickstart/repository/":
      ensure => 'link',
      owner  => 'aem',
      group  => 'aem',
      force  => true,
      target => "${author::aem_repo_mount_point}",
    }
  }

  class { '::config::aem_cleanup':
    require => Aem_aem['Ensure login page is ready'],
  }
}
