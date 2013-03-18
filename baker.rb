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

zones.each do |zone_name,zone_cfg|
  next if(zone_name != "prod2")
  chef_zone_url = "%s/%s-%s" % [CHEF_URL, zone_name, DOMAIN_NAME.gsub( /\./, '-' )]
  fs_client_key = "%s/.chef/keys/bakery-%s.%s.pem" % [ENV['HOME'], zone_name, DOMAIN_NAME]
  #Bakery::Log.debug( "Chef client key: %s" % fs_client_key )
  chef_srv = Chef::REST.new( chef_zone_url, "bakery", fs_client_key )
  #chef_nodes = chef_srv.get_rest( "/nodes" )

  zone_cfg["stacks"].each do |stack_name,stack_cfg|
    Bakery::Log.debug( "Stack: %s" % stack_name )
    merged = stacks[stack_name]
    merged["resources"].each do |name,cfg|
      cfg.deep_merge!(Marshal.load(Marshal.dump(zone_cfg["defaults"])))
    end
    merged["zone"] = zone_cfg
    merged["zone_name"] = zone_name
    stack = Bakery::Stack.new( merged )
    stack.check_cloud( chef_srv )
    #stack.enforce( chef_srv )
  end
end








exit

## Cache this so we don't have ot keep hitting the api.
# TODO: don't cache, go right to the api itself.
@config["zones"].each do |zone_name,zone_config|
  #chef_srv = Chef::REST.new( @cfg_left["url"], @cfg_left["client_name"], @client_key_left )
  chef_srv_url = "https://15.185.102.107/organizations/%s-ksonsoftware-com" % zone_name
  next if(zone_name != "prod1")
  @servers = get_servers( zone_name )
  @chef_srv = Chef::REST.new( chef_srv_url, 'bakery', "/home/krogebry/.chef/keys/%s.ksonsoftware.com.pem" % zone_name )

  ## Create input objects
  @config["inputs"].each do |input_name|
    Bakery::Log.info( "Input: %s" % input_name )    
    @logstash["resources"].each do |name,cfg|
      res_name = "%s-%s-%s-%s" % [@config["name"],@logstash["name"],name,input_name]
      merged = Marshal.load(Marshal.dump( zone_config.deep_merge( cfg.deep_merge({}) ))).deep_merge({
        "chef" => { 
          "tags" => [ input_name ]
        }
      })
      if(name == "input")
        merged.deep_merge({
          "chef" => { 
            "run_list" => ["recipe[log_pie::%s]" % input_name] 
          }
        })
      end
      res = mk_resource( res_name, merged, zone_name )
    end
  end
end
## Load the stack config.
stack_name = options[:stack_name]
@config = JSON::parse(File.read( "conf/%s.json" % stack_name ))
@logstash = JSON::parse(File.read( "conf/logstash.json" ))

@servers = ""
@chef_srv = ""

def mk_resource( name, cfg, zone_name )
      cfg["min"].times do |host_id|
        hostname = ("%s%i.%s.%s" % [name,host_id,zone_name,DOMAIN_NAME]).gsub( /_/,'-' )
        Bakery::Log.debug( "Resource (%s): %s" % [name,hostname] )

        if(!@servers.has_key?( hostname ))
          ## It doesn't exist, or it's still spinning up.
          ## Fire it up!!
          cmd_create_node = "hpcloud servers:add %s %i -i %i --key-name %s" % [hostname,cfg["flavor_id"],cfg["image_id"],zone_name]
          Bakery::Log.info( "Creating node: %s" % hostname)
          Bakery::Log.info( "Executing: %s" % cmd_create_node )
          if(options[:dry_run] == false)
            system( cmd_create_node )

            ## Make sure to delete the old client key
            system( "knife client delete %s -y" % hostname )
          end

        else
          ## It's up, now let's check to see if chef has the right info...
          Bakery::Log.info( "Node exists: %s" % hostname )

          ## This just sucks, but I can't trust a fully qualified chef object, but I do trust json. 
          begin
            node = JSON::parse(@chef_srv.get_rest( "/nodes/%s" % hostname ).to_json)
          rescue Net::HTTPServerException => e
            next ## it hasn't registered yet
          end

          ## Deal with the runlist
          #role = "role[%s_%s]" % [@logstash["name"],name]
          chef_run_list = (cfg["chef"].has_key?( "run_list" ) && cfg["chef"]["run_list"] != nil ? cfg["chef"]["run_list"] : [])
          node["run_list"] = chef_run_list 

          chef_tags = (cfg["chef"].has_key?( "tags" ) && cfg["chef"]["tags"] != nil ? cfg["chef"]["tags"] : [])
          node["normal"]["tags"] = chef_tags 

          ## Enforce the chef_env bits
          if(node["chef_environment"] == "_default")
            node["chef_environment"] = "prod"
          end

          Bakery::Log.debug( "Tags: %s" % node["normal"]["tags"].inspect )
          Bakery::Log.debug( "ChefEnv: %s" % node["chef_environment"] )
          Bakery::Log.debug( "Runlist: %s" % node["run_list"].inspect )

          if(options[:dry_run] == false)
            Bakery::Log.debug( "Updating node: %s" % hostname )
            @chef_srv.put_rest( "/nodes/%s" % hostname, node )
          end
        end
      end
end






