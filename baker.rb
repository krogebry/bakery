#!/usr/bin/ruby
##
# The baker puts everything together.
#
# knife acl add nodes input0.prod1.ksonsoftware.com update client input0.prod1.ksonsoftware.com
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
require 'rubygems'
require 'pp'
require 'chef'
require 'json'
require 'logger'
require 'optparse'
require 'hash_deep_merge'
require "./lib/bakery.rb"



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

DOMAIN_NAME = "ksonsoftware.com"

zones = JSON::parse(File.read( "conf/zones.json" ))

CHEF_URL = "https://15.185.102.107/organizations/"

stacks = {}
Dir.glob( "stacks/*.json" ).each do |f|
  stacks[File.basename(f).gsub( /\.json/,'' )] = JSON::parse(File.read( f ))
end

hpcloud = Bakery::HPCloud::Session.new()

logstash = JSON::parse(File.open( "conf/logstash.json" ))

zones.each do |zone_name,zone_cfg|
  next if(zone_name != "prod0")
  chef_zone_url = "%s/%s-%s" % [CHEF_URL, zone_name, DOMAIN_NAME.gsub( /\./, '-' )]
  fs_client_key = "%s/.chef/keys/bakery-%s.%s.pem" % [ENV['HOME'], zone_name, DOMAIN_NAME]
  chef_srv = Chef::REST.new( chef_zone_url, "bakery", fs_client_key )

  zone_cfg["stacks"].each do |stack_name,stack_cfg|
    Bakery::Log.debug( "Stack: %s" % stack_name )

    merged = stacks[stack_name]
    pp merged
    merged["resources"].each do |name,cfg|
      cfg.deep_merge!(Marshal.load(Marshal.dump(zone_cfg["defaults"])))
    end
    merged["zone"] = zone_cfg
    merged["zone_name"] = zone_name
    stack = Bakery::Stack.new( merged )
    stack.check_cloud( chef_srv )

    ## Deal with the inputs
    #merged["inputs"].each do |input|
      #logstash["resources"].each do |name,cfg|
        #cfg.deep_merge!(Marshal.load(Marshal.dump(zone_cfg["defaults"])))
      #end
      #merged["zone"] = zone_cfg
      #merged["zone_name"] = zone_name
    #end
  end
end

