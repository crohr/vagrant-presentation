# Virtualize your app's development environment

(This is a one-time process).

    $ rails new vagrant-presentation
    $ cd vagrant-presentation
    $ rails g scaffold user name:string

Modify `config/database.yml` with mysql2 adapter. 

    $ rake db:setup
    rake aborted!
    Please install the mysql2 adapter: `gem install activerecord-mysql2-adapter` (mysql2 is not part of the bundle. Add it to Gemfile.)

Add `mysql2` to Gemfile, and `thin`.

    $ bundle install
    $ rake db:setup
    rake aborted!
    Can't connect to local MySQL server through socket '/tmp/mysql.sock' (2)

Time to add a mysql-server somewhere.

## Enter Vagrant

    $ gem install vagrant

    $ vagrant box add squeeze-x64 http://boxes.dev/debian-squeeze-x64-puppet-v4.1.12.box
    [vagrant] Downloading with Vagrant::Downloaders::HTTP...
    [vagrant] Downloading box: http://boxes.dev/debian-squeeze-x64-puppet-v4.1.12.box
    [vagrant] Extracting box...
    [vagrant] Verifying box...
    [vagrant] Cleaning up downloaded box...

    $ vagrant init squeeze-x64

    $ vim Vagrantfile
    # box url
    
    $ vagrant up
    [default] Importing base box 'squeeze-x64'...
    [default] Matching MAC address for NAT networking...
    [default] Clearing any previously set forwarded ports...
    [default] Forwarding ports...
    [default] -- 22 => 2222 (adapter 1)
    [default] Creating shared folders metadata...
    [default] Clearing any previously set network interfaces...
    [default] Booting VM...
    [default] Waiting for VM to boot. This can take a few minutes.
    [default] VM booted and ready for use!
    [default] Mounting shared folders...
    [default] -- v-root: /vagrant

    $ vagrant ssh

Show VirtualBox GUI.

    $ rake db:setup

Time to add a mysql-server to our box (manually, just to show how to forward ports, and to understand the basics).

    $ vagrant ssh
    vagrant@vagrant-debian-squeeze:~$ sudo apt-get update
    vagrant@vagrant-debian-squeeze:~$ sudo apt-get install mysql-server -y

Check install:

    vagrant@vagrant-debian-squeeze:~$ mysql -u root

Port forwarding:

    # vi Vagrantfile
    # config.vm.forward_port 3306, 13306
    $ vagrant reload
    [default] Attempting graceful shutdown of VM...
    [default] Clearing any previously set forwarded ports...
    [default] Forwarding ports...
    [default] -- 22 => 2222 (adapter 1)
    [default] -- 3306 => 13306 (adapter 1)
    [default] Creating shared folders metadata...
    [default] Clearing any previously set network interfaces...
    [default] Booting VM...
    [default] Waiting for VM to boot. This can take a few minutes.
    [default] VM booted and ready for use!
    [default] Mounting shared folders...
    [default] -- v-root: /vagrant

Test port forwarding:

    $ mysql -u root -h 127.0.0.1 -P 13306
    ERROR 2013 (HY000): Lost connection to MySQL server at 'reading initial communication packet', system error: 0

Allow incoming connections and create db user:

    vagrant@vagrant-debian-squeeze:~# echo "[mysqld]
    bind-address = 0.0.0.0" > /etc/mysql/conf.d/custom.cnf
    vagrant@vagrant-debian-squeeze:~# mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'crohr'@'%' IDENTIFIED BY 'pass';"
    vagrant@vagrant-debian-squeeze:~# /etc/init.d/mysql restart

    $ mysql -u crohr -h 127.0.0.1 -P 13306 -p

Test (add `host: 127.0.0.1`, `port: 13306`, `username: crohr`, and `password: pass` to `config/database.yml`):

    $ rake db:setup
    $ rake db:migrate
    $ rails s

    # create some users, and inspect the database on the VM:
    $ mysql -u crohr -h 127.0.0.1 -P 13306 -p

    # make sure it fails if we suspend the VM:
    $ vagrant suspend
    $ mysql -u crohr -h 127.0.0.1 -P 13306 -p

Works, we have a VM with an isolated mysql-server, but cumbersome.

## Enter Puppet (presentation).

Let's do the same thing as before but with Puppet.

Put all those lines in a puppet manifest.

    $ mkdir -p puppet/manifests

Open `puppet/manifests/vagrant-presentation.pp` and paste the following:

    # puppet/manifests/vagrant-presentation.pp
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

Edit Vagrantfile to reflect the puppet manifest name and location:

    config.vm.provision :puppet do |puppet|
      puppet.manifests_path = "puppet/manifests"
      puppet.manifest_file  = "vagrant-presentation.pp"
    end

Then, recreate the full VM:

    $ vagrant destroy && vagrant up # or vagrant reload
    $ mysql -u crohr -h 127.0.0.1 -P 13306 -p # should pass

If error, just do:

    $ vagrant provision

Test that everything is working:

    $ rails s

Now let's add Redis interaction:

    # config/initializers/redis.rb
    REDIS = Redis.new
    print "REDIS is saying: "
    puts REDIS.ping

    $ rails s
    Connection refused - Unable to connect to Redis on 127.0.0.1:6379 (Errno::ECONNREFUSED)

Add it to our puppet recipe, this time as a module:

    $ mkdir -p puppet/modules/redis/{manifests,templates,files}

    # puppet/modules/redis/manifests/init.pp
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

Add template for configuration (change `bind 127.0.0.1` to `bind <%= bind_address %>`):

    # puppet/modules/redis/templates/redis.conf.erb
    # Redis configuration file example

    # By default Redis does not run as a daemon. Use 'yes' if you need it.
    # Note that Redis will write a pid file in /var/run/redis.pid when daemonized.
    daemonize yes

    # When run as a daemon, Redis write a pid file in /var/run/redis.pid by default.
    # You can specify a custom pid file location here.
    pidfile /var/run/redis.pid

    # Accept connections on the specified port, default is 6379
    port 6379

    # If you want you can bind a single interface, if the bind option is not
    # specified all the interfaces will listen for connections.
    #
    bind 127.0.0.1

    # Close the connection after a client is idle for N seconds (0 to disable)
    timeout 300

    # Set server verbosity to 'debug'
    # it can be one of:
    # debug (a lot of information, useful for development/testing)
    # notice (moderately verbose, what you want in production probably)
    # warning (only very important / critical messages are logged)
    loglevel notice

    # Specify the log file name. Also 'stdout' can be used to force
    # the demon to log on the standard output. Note that if you use standard
    # output for logging but daemonize, logs will be sent to /dev/null
    logfile /var/log/redis/redis-server.log

    # Set the number of databases. The default database is DB 0, you can select
    # a different one on a per-connection basis using SELECT <dbid> where
    # dbid is a number between 0 and 'databases'-1
    databases 16

    ################################ SNAPSHOTTING  #################################
    #
    # Save the DB on disk:
    #
    #   save <seconds> <changes>
    #
    #   Will save the DB if both the given number of seconds and the given
    #   number of write operations against the DB occurred.
    #
    #   In the example below the behaviour will be to save:
    #   after 900 sec (15 min) if at least 1 key changed
    #   after 300 sec (5 min) if at least 10 keys changed
    #   after 60 sec if at least 10000 keys changed
    save 900 1
    save 300 10
    save 60 10000

    # Compress string objects using LZF when dump .rdb databases?
    # For default that's set to 'yes' as it's almost always a win.
    # If you want to save some CPU in the saving child set it to 'no' but
    # the dataset will likely be bigger if you have compressible values or keys.
    rdbcompression yes

    # The filename where to dump the DB
    dbfilename dump.rdb

    # For default save/load DB in/from the working directory
    # Note that you must specify a directory not a file name.
    dir /var/lib/redis

    ################################# REPLICATION #################################

    # Master-Slave replication. Use slaveof to make a Redis instance a copy of
    # another Redis server. Note that the configuration is local to the slave
    # so for example it is possible to configure the slave to save the DB with a
    # different interval, or to listen to another port, and so on.
    #
    # slaveof <masterip> <masterport>

    # If the master is password protected (using the "requirepass" configuration
    # directive below) it is possible to tell the slave to authenticate before
    # starting the replication synchronization process, otherwise the master will
    # refuse the slave request.
    #
    # masterauth <master-password>

    ################################## SECURITY ###################################

    # Require clients to issue AUTH <PASSWORD> before processing any other
    # commands.  This might be useful in environments in which you do not trust
    # others with access to the host running redis-server.
    #
    # This should stay commented out for backward compatibility and because most
    # people do not need auth (e.g. they run their own servers).
    #
    # requirepass foobared

    ################################### LIMITS ####################################

    # Set the max number of connected clients at the same time. By default there
    # is no limit, and it's up to the number of file descriptors the Redis process
    # is able to open. The special value '0' means no limts.
    # Once the limit is reached Redis will close all the new connections sending
    # an error 'max number of clients reached'.
    #
    # maxclients 128

    # Don't use more memory than the specified amount of bytes.
    # When the memory limit is reached Redis will try to remove keys with an
    # EXPIRE set. It will try to start freeing keys that are going to expire
    # in little time and preserve keys with a longer time to live.
    # Redis will also try to remove objects from free lists if possible.
    #
    # If all this fails, Redis will start to reply with errors to commands
    # that will use more memory, like SET, LPUSH, and so on, and will continue
    # to reply to most read-only commands like GET.
    #
    # WARNING: maxmemory can be a good idea mainly if you want to use Redis as a
    # 'state' server or cache, not as a real DB. When Redis is used as a real
    # database the memory usage will grow over the weeks, it will be obvious if
    # it is going to use too much memory in the long run, and you'll have the time
    # to upgrade. With maxmemory after the limit is reached you'll start to get
    # errors for write operations, and this may even lead to DB inconsistency.
    #
    # maxmemory <bytes>

    ############################## APPEND ONLY MODE ###############################

    # By default Redis asynchronously dumps the dataset on disk. If you can live
    # with the idea that the latest records will be lost if something like a crash
    # happens this is the preferred way to run Redis. If instead you care a lot
    # about your data and don't want to that a single record can get lost you should
    # enable the append only mode: when this mode is enabled Redis will append
    # every write operation received in the file appendonly.log. This file will
    # be read on startup in order to rebuild the full dataset in memory.
    #
    # Note that you can have both the async dumps and the append only file if you
    # like (you have to comment the "save" statements above to disable the dumps).
    # Still if append only mode is enabled Redis will load the data from the
    # log file at startup ignoring the dump.rdb file.
    #
    # The name of the append only file is "appendonly.log"
    #
    # IMPORTANT: Check the BGREWRITEAOF to check how to rewrite the append
    # log file in background when it gets too big.

    appendonly no

    # The fsync() call tells the Operating System to actually write data on disk
    # instead to wait for more data in the output buffer. Some OS will really flush 
    # data on disk, some other OS will just try to do it ASAP.
    #
    # Redis supports three different modes:
    #
    # no: don't fsync, just let the OS flush the data when it wants. Faster.
    # always: fsync after every write to the append only log . Slow, Safest.
    # everysec: fsync only if one second passed since the last fsync. Compromise.
    #
    # The default is "always" that's the safer of the options. It's up to you to
    # understand if you can relax this to "everysec" that will fsync every second
    # or to "no" that will let the operating system flush the output buffer when
    # it want, for better performances (but if you can live with the idea of
    # some data loss consider the default persistence mode that's snapshotting).

    appendfsync always
    # appendfsync everysec
    # appendfsync no

    ############################### ADVANCED CONFIG ###############################

    # Glue small output buffers together in order to send small replies in a
    # single TCP packet. Uses a bit more CPU but most of the times it is a win
    # in terms of number of queries per second. Use 'yes' if unsure.
    glueoutputbuf yes

    # Use object sharing. Can save a lot of memory if you have many common
    # string in your dataset, but performs lookups against the shared objects
    # pool so it uses more CPU and can be a bit slower. Usually it's a good
    # idea.
    #
    # When object sharing is enabled (shareobjects yes) you can use
    # shareobjectspoolsize to control the size of the pool used in order to try
    # object sharing. A bigger pool size will lead to better sharing capabilities.
    # In general you want this value to be at least the double of the number of
    # very common strings you have in your dataset.
    #
    # WARNING: object sharing is experimental, don't enable this feature
    # in production before of Redis 1.0-stable. Still please try this feature in
    # your development environment so that we can test it better.
    shareobjects no
    shareobjectspoolsize 1024

Include the class in your app manifest:

    # puppet/manifests/vagrant-presentation.pp

    class {'redis':
      bind_address => "0.0.0.0"
    }

Change host and port of redis initializer:

    # config/initializers/redis.rb
    REDIS = Redis.new host: "127.0.0.1", port: 16379

Add the port forwarding to the Vagrantfile:

    # Vagrantfile
    config.vm.forward_port 6379, 16379

Configure your Vagrantfile to look for modules:

    config.vm.provision :puppet, :module_path => "puppet/modules" do |puppet|

Reload:

    $ vagrant reload
    [default] Attempting graceful shutdown of VM...
    [default] Clearing any previously set forwarded ports...
    [default] Forwarding ports...
    [default] -- 22 => 2222 (adapter 1)
    [default] -- 3306 => 13306 (adapter 1)
    [default] -- 6379 => 16379 (adapter 1)
    [default] Creating shared folders metadata...
    [default] Clearing any previously set network interfaces...
    [default] Booting VM...
    [default] Waiting for VM to boot. This can take a few minutes.
    [default] VM booted and ready for use!
    [default] Mounting shared folders...
    [default] -- v-root: /vagrant
    [default] -- manifests: /tmp/vagrant-puppet/manifests
    [default] -- v-pp-m0: /tmp/vagrant-puppet/modules-0
    [default] Running provisioner: Vagrant::Provisioners::Puppet...
    [default] Running Puppet with /tmp/vagrant-puppet/manifests/vagrant-presentation.pp...
    stdin: is not a tty
    notice: /Stage[main]/Redis/File[/etc/redis/redis.conf]/content: content changed '{md5}a19bad63017ec19def2c3a8a07bdc362' to '{md5}2e7b4b6e37a56dd0c8c1b7573cff2bce'

    notice: /Stage[main]/Redis/Service[redis-server]: Triggered 'refresh' from 1 events
    notice: /Stage[main]//Exec[add-mysql-user]/returns: executed successfully

Try again:

    $ rails s
    ...
    REDIS is saying:PONG

Note: `puppet/modules` folder could be a submodule which references
existing modules (i.e. reuse), and then you just parametrize the
manifest with the correct configuration parameters.

You could do the same with the MySQL class [exercise left to the
reader].

## Share

Now git add everything, create new repo on github, push:

    $ git init
    $ git add .
    $ git commit -m "All in."
    # create repo on github
    $ git remote add ...
    $ git push ...

Destroy everything:

    $ vagrant destroy
    Are you sure you want to destroy the 'default' VM? [Y/N] Y
    [default] Forcing shutdown of VM...
    [default] Destroying VM and associated drives...

    $ vagrant box remove squeeze-x64
    [vagrant] Deleting box 'squeeze-x64'...

    $ rm -rf vagrant-presentation

Ok, let's clone the repo and try to launch the app:

    $ git clone git@github.com:crohr/trash.git
    $ cd trash
    $ bundle install
    $ vagrant up
    [default] Box squeeze-x64 was not found. Fetching box from specified URL...
    [vagrant] Downloading with Vagrant::Downloaders::HTTP...
    [vagrant] Downloading box: http://boxes.dev/debian-squeeze-x64-puppet-v4.1.12.box
    [vagrant] Extracting box...
    [vagrant] Verifying box...
    [vagrant] Cleaning up downloaded box...
    [default] Importing base box 'squeeze-x64'...
    [default] Matching MAC address for NAT networking...
    [default] Clearing any previously set forwarded ports...
    [default] Forwarding ports...
    [default] -- 22 => 2222 (adapter 1)
    [default] -- 3306 => 13306 (adapter 1)
    [default] -- 6379 => 16379 (adapter 1)
    [default] Creating shared folders metadata...
    [default] Clearing any previously set network interfaces...
    [default] Booting VM...
    [default] Waiting for VM to boot. This can take a few minutes.
    [default] VM booted and ready for use!
    [default] Mounting shared folders...
    [default] -- v-root: /vagrant
    [default] -- manifests: /tmp/vagrant-puppet/manifests
    [default] -- v-pp-m0: /tmp/vagrant-puppet/modules-0
    [default] Running provisioner: Vagrant::Provisioners::Puppet...
    [default] Running Puppet with /tmp/vagrant-puppet/manifests/vagrant-presentation.pp...
    stdin: is not a tty
    notice: /Stage[main]/Redis/Package[redis-server]/ensure: ensure changed 'purged' to 'present'
    notice: /Stage[main]/Redis/File[/etc/redis/redis.conf]/content: content changed '{md5}a19bad63017ec19def2c3a8a07bdc362' to '{md5}2e7b4b6e37a56dd0c8c1b7573cff2bce'

    notice: /Stage[main]/Redis/Service[redis-server]: Triggered 'refresh' from 1 events
    notice: /Stage[main]//Package[mysql-server]/ensure: ensure changed 'purged' to 'present'
    notice: /Stage[main]//File[/etc/mysql/conf.d/custom.cnf]/ensure: defined content as '{md5}aea46f45d8499176de3cb888405788f2'
    notice: /Stage[main]//Service[mysqld]: Triggered 'refresh' from 1 events
    notice: /Stage[main]//Exec[add-mysql-user]/returns: executed successfully

    $ rake db:setup
    $ rails s

Win!

    $ vagrant suspend
    $ rails s
    $ vagrant resume
    $ rails s