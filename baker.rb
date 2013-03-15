#!/usr/bin/ruby
##
# The baker puts everything together.
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

JSON.create_id = nil

module Baker ; end
Baker::Log = Logger.new( STDOUT )
Baker::Log.level = Logger::DEBUG

@options = { :dry_run => false }
OptionParser.new do |opts|
opts.banner = "Usage: baker.rb [options]"

  opts.on( "-v", "--[no-]verbose", "Run verbosely" ) do |v|
    @options[:verbose] = v
  end

  opts.on( "-d", "--dry-run", "Dry run, don't actually do anything" ) do |v|
    @options[:dry_run] = true
  end

  #opts.on( "-s", "--set-hostname", "Set the hostname" ) do |v|
    #options[:set_hostname] = true
  #end

  #opts.on( "-r", "--set-run-list", "Set the run_list" ) do |v|
    #options[:set_run_list] = true
  #end

  #opts.on( "-a", "--set-acl", "Set/fix the acl's" ) do |v|
    #options[:set_acl] = true
  #end

  #opts.on( "-k", "--keygen", "Remove old keys" ) do |v|
    #options[:keygen] = true
  #end

  opts.on( "-s", "--stack-name STACK_NAME", "Name of stack config" ) do |v|
    @options[:stack_name] = v
  end

  opts.on( "-f", "--flush-cache", "Flush cache" ) do |v|
    @options[:flush_cache] = true
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

#if(options[:set_hostname] == true)
  #f_set_hostname = File.open( "cmd_set_hostname","w" )
#end

#if(options[:set_run_list] == true)
  #f_set_run_list = File.open( "cmd_set_run_list","w" )
#end

#if(options[:set_acl] == true)
  #f_set_acl = File.open( "cmd_set_acl","w" )
#end

stack_name = @options[:stack_name]

## Load the stack config.
@config = JSON::parse(File.read( "conf/%s.json" % stack_name ))
@logstash = JSON::parse(File.read( "conf/logstash.json" ))

#components = config["components"]
#classes = config["classes"]

#system( "rm -rf hpcloud.json 1&2 > /dev/null" ) if(options[:flush_cache] == true)

def get_servers( zone_name )
  fs_cache_file = "hpcloud-%s.json" % zone_name 
  servers = {}

  if(File.exists?( fs_cache_file )) 
    servers = JSON::parse(File.read( fs_cache_file ))

  else
    Baker::Log.info( "Taling to hpcloud for server list..." )
    hpcloud_servers = `hpcloud servers`.split( "\n" )
    Baker::Log.info( "Got server list" )
    if(hpcloud_servers.size > 1)
      srv_fields = hpcloud_servers[1].split().map{|l| l if(l.match( /[a-z]/ )) }.compact
      hpcloud_servers.each do |row|
        next if(!row.match( /ACTIVE/ ))
        i=-1
        srv = {}
        data = row.split( "|" ).map{|f| f.strip }
        data.shift 
        data.map{|f| srv[srv_fields[i+=1]] = f }
        servers[srv["name"]] = srv
      end
    end ## has servers

    f = File.open( fs_cache_file,"w" )
    f.puts( servers.to_json )
    f.close()

  end ## exists?( cache )
  return servers
end

def mk_resource( name, cfg, zone_name )
      cfg["min"].times do |host_id|
        hostname = ("%s%i.%s.%s" % [name,host_id,zone_name,DOMAIN_NAME]).gsub( /_/,'-' )
        Baker::Log.debug( "Resource (%s): %s" % [name,hostname] )

        if(!@servers.has_key?( hostname ))
          ## It doesn't exist, or it's still spinning up.
          ## Fire it up!!
          cmd_create_node = "hpcloud servers:add %s %i -i %i --key-name %s" % [hostname,cfg["flavor_id"],cfg["image_id"],zone_name]
          Baker::Log.info( "Creating node: %s" % hostname)
          Baker::Log.info( "Executing: %s" % cmd_create_node )
          if(@options[:dry_run] == false)
            system( cmd_create_node )

            ## Make sure to delete the old client key
            system( "knife client delete %s -y" % hostname )
          end

        else
          ## It's up, now let's check to see if chef has the right info...
          Baker::Log.info( "Node exists: %s" % hostname )

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

          #if(!node["run_list"].include?( role ))
            #Baker::Log.info( "Adding run_list item: %s" % role )
            #node["run_list"].push( role )
          #end

          chef_tags = (cfg["chef"].has_key?( "tags" ) && cfg["chef"]["tags"] != nil ? cfg["chef"]["tags"] : [])
          node["normal"]["tags"] = chef_tags 

          #if(!node["normal"]["tags"].include?( input_name ))
            #Baker::Log.info( "Adding tag item: %s" % input_name )
            #node["normal"]["tags"].push( input_name )
          #end

          ## Enforce the chef_env bits
          if(node["chef_environment"] == "_default")
            node["chef_environment"] = "prod"
          end

          Baker::Log.debug( "Tags: %s" % node["normal"]["tags"].inspect )
          Baker::Log.debug( "ChefEnv: %s" % node["chef_environment"] )
          Baker::Log.debug( "Runlist: %s" % node["run_list"].inspect )

          if(@options[:dry_run] == false)
            Baker::Log.debug( "Updating node: %s" % hostname )
            @chef_srv.put_rest( "/nodes/%s" % hostname, node )
          end
        end
      end
end

DOMAIN_NAME = "ksonsoftware.com"

@servers = ""
@chef_srv = ""

#require 'active_support/core_ext/hash/deep_merge'
require 'hash_deep_merge'

## Cache this so we don't have ot keep hitting the api.
# TODO: don't cache, go right to the api itself.
@config["zones"].each do |zone_name,zone_config|
  #chef_srv = Chef::REST.new( @cfg_left["url"], @cfg_left["client_name"], @client_key_left )
  chef_srv_url = "https://15.185.102.107/organizations/%s-ksonsoftware-com" % zone_name

  #zone_name = "prod2"
  #zone = config["zones"][zone_name]
  next if(zone_name != "prod2")

  @servers = get_servers( zone_name )
  @chef_srv = Chef::REST.new( chef_srv_url, 'bakery', "/home/krogebry/.chef/keys/%s.ksonsoftware.com.pem" % zone_name )

  @config["resources"].each do |name,cfg|
    res_name = "%s-%s" % [@config["name"],name]
    Baker::Log.info( "Resource: %s" % res_name )    
    merged = zone_config.merge( cfg )
    res = mk_resource( res_name, merged, zone_name )
  end

  ## Create input objects
  @config["inputs"].each do |input_name|
    Baker::Log.info( "Input: %s" % input_name )    
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



