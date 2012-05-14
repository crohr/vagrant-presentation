package {"mysql-server":
  ensure => installed
}

service {"mysqld":
  name => "mysql",
  ensure => running,
  require => Package["mysql-server"]
}

file { "/etc/mysql/conf.d/custom.cnf":
 mode => 644, owner => root, group => root,
 content => "[mysqld]\nbind-address = 0.0.0.0",
 notify => Service["mysqld"],
 require => Package["mysql-server"];
}

exec { "add-mysql-user":
  command => "/usr/bin/mysql -u root -e \"GRANT ALL PRIVILEGES ON *.* TO 'crohr'@'%' IDENTIFIED BY 'pass';\"",
  require => Package["mysql-server"]
}

class {'redis':
  bind_address => "0.0.0.0"
}