class redis($bind_address = "127.0.0.1") {
  package {"redis-server":
    ensure => installed
  }

  service {"redis-server":
    ensure => running,
    require => Package["redis-server"]
  }

  file { "/etc/redis/redis.conf":
   mode => 644, owner => root, group => root,
   content => template("redis/redis.conf.erb"),
   notify => Service["redis-server"],
   require => Package["redis-server"];
  }
}