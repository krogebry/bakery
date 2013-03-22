#!/usr/bin/ruby
##
# The baker puts everything together.
#
# knife acl add nodes fat-es-master0.prod2.ksonsoftware.com update client fat-es-master0.prod2.ksonsoftware.com
#
# pssh -P -h hosts_all -l ubuntu -p 10 -t 0 -x"-i /home/krogebry/.ssh/keys/aw0_az1_prod0.pem" "sudo chef-client"
# pssh -P -h hosts_all -l ubuntu -p 10 -t 0 -x"-i /home/krogebry/.ssh/keys/prod2.ksonsoftware.com.pem" "sudo chef-client"
# for node_id in `hpcloud servers|grep prod0.ksonsoftware.com|awk '{print $2}'`; do   hpcloud servers:remove $node_id; done

# for node_id in `hpcloud servers|grep prod2.ksonsoftware.com|awk '{print $2}'`; do   hpcloud servers:remove $node_id; done
# for node in `knife node list|grep "logstash-"`; do   knife node delete $node -y ; knife client delete $node -y; done

# for node in `knife node list|grep "logstash-"`; do   knife node delete $node -y ; done
# for node in `knife client list|grep "logstash-"`; do   knife client delete $node -y ; done
# for node in `knife node list|grep ".novalocal"|grep logstash`; do   knife node delete $node -y ; done

# Nodes and clients
# for node in `knife node list|grep "logstash-"`; do   knife node delete $node -y ; knife client delete $node -y; done
#
# Reset es
# pssh -h hosts_elasticsearch -l ubuntu -p 10 -t 0 -x"-i /home/krogebry/.ssh/keys/aw0_az1_prod0.pem" "sudo service elasticsearch stop ; sudo rm -rf /mnt/elasticsearch/data/elasticsearch/ ; sudo service elasticsearch start"
FS_ROOT = File.dirname(File.expand_path(File.join( __FILE__, ".." ))) 
require 'rubygems'
require 'pp'
require 'chef'
require 'json'
require 'logger'
require 'optparse'
require 'hash_deep_merge'
require "%s/lib/bakery.rb" % FS_ROOT
require "%s/conf/bakery.rb" % FS_ROOT



options = { :dry_run => false, :verbose => false }
OptionParser.new do |opts|
opts.banner = "Usage: baker.rb [options]"

  opts.on( "-v", "--[no-]verbose", "Run verbosely" ) do |v|
    options[:verbose] = v
  end

  opts.on( "-d", "--dry-run", "Dry run, don't actually do anything" ) do |v|
    options[:dry_run] = true
  end

  opts.on( "-s", "--stack-name STACK_NAME", "Name of stack config" ) do |v|
    options[:stack_name] = v
  end

  opts.on( "-f", "--flush-cache", "Flush cache" ) do |v|
    options[:flush_cache] = true
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

Bakery::Log.level = Logger::DEBUG if(options[:verbose] == true)



## Load the zones 
zones = JSON::parse(File.read( "%s/conf/zones.json" % FS_ROOT ))

## Load the stacks
#stacks = {}
#Dir.glob( "%s/stacks/*.json" % FS_ROOT ).each do |f|
  #stacks[File.basename(f).gsub( /\.json/,'' )] = JSON::parse(File.read( f ))
#end

## Load the components
#components = {}
#Dir.glob( "%s/stacks/components/*.json" % FS_ROOT ).each do |f|
  #components[File.basename(f).gsub( /\.json/,'' )] = JSON::parse(File.read( f ))
#end
#logstash = JSON::parse(File.open( "conf/logstash.json" ))

ADMIN_KEYS = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBiMMU5ptaEJLyoqowcACbcp8j0LXzNk/7pEtdZVqSFNH4LmkSe0qdeoe5vj4WDS0TgRA0e64H/HAEbTXJjk1212E6rZOd9ffeGBHiHUr+/aVc7x1clcv0bxQM+ox+eyrSMNC12En2zMQXrNP8iJAo7xvYf1AgzbH/YkjmOmHPslL/ILxBHTQ2KGKf9IMdqEh6nRCyrz81K2sTR+XFtZcIfT+C5VMUXJNhKdRhh1i+R+UQ1c9JEIwQTOcNF2Mdl1khpFGri3zIjvCFC+vDhUOe6a2VYWzO96N4U96EjKoJG4/NNHmIlSXlVhkvmzNiUu7mRG2zOnfPEOimD/k5YFFz krogebry@krogebry-workstation"

#f = File.open( "%s/tmp/hosts" % FS_ROOT, "w" )
zones.each do |zone_name,zone_cfg|
  zone = Bakery::Zone.new( zone_name, zone_cfg )
  zone.manage_cloud()
  #f.puts(zone.servers.map{|srv| srv[".join( "\n" ))
end
#f.close

