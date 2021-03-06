define config::cloudwatchlogs_aem (
  $aem_id,
  $service_name = lookup('config::base::awslogs_service_name')
) {

  $aem_log_dir = "/opt/aem/${aem_id}/crx-quickstart/logs"
  $aem_apache_datetime_files = [ 'access.log', 'request.log' ]
  $aem_stdout_datetime_files = [ 'stdout.log', 'error.log', 'history.log' ]
  $aem_iso8601_datetime_files = [ 'gc_logs.log' ]
  $aem_unknown_datetime_files = [
    # TODO Get example log files to determine `datetime_format`
    'audit.log', 'auditlog.log', 'upgrade.log',
  ]
  $aem_unknown_datetime_files.each |$file| {
    cloudwatchlogs::log { "${aem_log_dir}/${file}":
      notify          => Service[$service_name],
    }
  }
  $aem_apache_datetime_files.each |$file| {
    cloudwatchlogs::log { "${aem_log_dir}/${file}":
      datetime_format => '%d/%b/%Y:%H:%M:%S %z',
      notify          => Service[$service_name],
    }
  }
  $aem_stdout_datetime_files.each |$file| {
    cloudwatchlogs::log { "${aem_log_dir}/${file}":
      datetime_format => '%d.%m.%Y %H:%M:%S.%f',
      notify          => Service[$service_name],
    }
  }
  $aem_iso8601_datetime_files.each |$file| {
    cloudwatchlogs::log { "${aem_log_dir}/${file}":
      datetime_format => '%Y-%m-%dT%H:%M:%S.%f%z',
      notify          => Service[$service_name],
    }
  }

}
