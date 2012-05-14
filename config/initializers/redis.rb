REDIS = Redis.new host: "127.0.0.1", port: 16379
print "REDIS is saying: "
puts REDIS.ping