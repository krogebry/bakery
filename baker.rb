#!/usr/bin/ruby
##
# The baker puts everything together.
#
# pssh -P -h hosts_authlog_input -l ubuntu -p 10 -t 0 -x"-i /home/krogebry/.ssh/keys/aw0_az1_prod0.pem" "sudo chef-client"
# for node_id in `hpcloud servers|grep prod0.ksonsoftware.com|awk '{print $2}'`; do   hpcloud servers:remove $node_id; done
# for node in `knife node list|grep "logstash-"`; do   knife client delete $node -y ; knife node delete $node -y; done
# for node in `knife client list|grep "logstash-"`; do   knife client delete $node -y ; done
# for node in `knife node list|grep ".novalocal"|grep logstash`; do   knife node delete $node -y ; done
# Reset es
# pssh -h hosts_elasticsearch -l ubuntu -p 10 -t 0 -x"-i /home/krogebry/.ssh/keys/aw0_az1_prod0.pem" "sudo service elasticsearch stop ; sudo rm -rf /mnt/elasticsearch/data/elasticsearch/ ; sudo service elasticsearch start"
require 'rubygems'
require 'pp'
require 'json'
require 'logger'
require 'optparse'

module Baker ; end
Baker::Log = Logger.new( STDOUT )
Baker::Log.level = Logger::DEBUG

options = { :dry_run => false }
OptionParser.new do |opts|
opts.banner = "Usage: baker.rb [options]"

  opts.on( "-v", "--[no-]verbose", "Run verbosely" ) do |v|
    options[:verbose] = v
  end

  opts.on( "-d", "--dry-run", "Dry run, don't actually do anything" ) do |v|
    options[:dry_run] = true
  end

  opts.on( "-s", "--set-hostname", "Set the hostname" ) do |v|
    options[:set_hostname] = true
  end

  opts.on( "-r", "--set-run-list", "Set the run_list" ) do |v|
    options[:set_run_list] = true
  end

  opts.on( "-a", "--set-acl", "Set/fix the acl's" ) do |v|
    options[:set_acl] = true
  end

  opts.on( "-k", "--keygen", "Remove old keys" ) do |v|
    options[:keygen] = true
  end

  opts.on( "-f", "--flush-cache", "Flush cache" ) do |v|
    options[:flush_cache] = true
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

if(options[:set_hostname] == true)
  f_set_hostname = File.open( "cmd_set_hostname","w" )
end

if(options[:set_run_list] == true)
  f_set_run_list = File.open( "cmd_set_run_list","w" )
end

if(options[:set_acl] == true)
  f_set_acl = File.open( "cmd_set_acl","w" )
end


## Load the stack config.
config = JSON::parse(File.read( "conf/logstash.json" ))

system( "unlink hpcloud.json 1&2 > /dev/null" ) if(options[:flush_cache] == true)

## Cache this.
if(File.exists?( "hpcloud.json" )) 
  servers = JSON::parse(File.read( "hpcloud.json" ))

else
  hpcloud_servers = `hpcloud servers`.split( "\n" )
  #pp hpcloud_servers
  srv_fields = hpcloud_servers[1].split().map{|l| l if(l.match( /[a-z]/ )) }.compact
  #pp srv_fields
  #exit
  servers = {}
  hpcloud_servers.each do |row|
    next if(!row.match( /ACTIVE/ ))
    i=-1
    srv = {}
    data = row.split( "|" ).map{|f| f.strip }
    data.shift 
    data.map{|f| srv[srv_fields[i+=1]] = f }
    #pp srv
    servers[srv["name"]] = srv
  end

  f = File.open( "hpcloud.json","w" )
  f.puts( servers.to_json )
  f.close()
end

all_hosts = []


config["resources"].each do |name,res_cfg|

  hosts = []

  #hpcloud servers:add logstash_syslog_input0.prod0.ksonsoftware.com 100 -i 79882 --key-name prod0
  res_cfg["min"].times do |host_id|
    hostname = "logstash-%s%i.prod0.ksonsoftware.com" % [name,host_id]
    #puts "Hostname: %s" % hostname
    #user_data = {
      #"chef_runlist" => "[role[logstash_%s]]" % name
    #}.map{|k,v| "%s=%s" % [k,v] }.join( "," )

    if(!servers.has_key?( hostname ))
      #cmd_create_node = "hpcloud servers:add %s %i -i %i --key-name prod0 -m \"%s\"" % [hostname,res_cfg["flavor_id"],res_cfg["image_id"],user_data]
      cmd_create_node = "hpcloud servers:add %s %i -i %i --key-name prod0" % [hostname,res_cfg["flavor_id"],res_cfg["image_id"]]
      #puts cmd_create_node
      Baker::Log.info( "Creating node: %s" % cmd_create_node )
      if(options[:dry_run] == false)
        res = `#{cmd_create_node}`
        Baker::Log.debug( "Res: %s" % res )
      end

    else
      hosts.push( servers[hostname]["public_ip"] )
      all_hosts.push( servers[hostname]["public_ip"] )

      if(options[:keygen] == true)
        cmd_clear_key = "ssh-keygen -f '/home/krogebry/.ssh/known_hosts' -R %s 2>&1" % servers[hostname]["public_ip"]
        Baker::Log.info( "Removing key: %s" % cmd_clear_key )
        if(options[:dry_run] == false)
          res = `#{cmd_clear_key}`
          Baker::Log.debug( "Res: %s" % res )
        end
      end

      if(options[:set_hostname] == true)
        cmd_set_hostname = "ssh -i /home/krogebry/.ssh/keys/aw0_az1_prod0.pem ubuntu@%s \"sudo hostname %s ; sudo bash -c \\\"echo '%s %s' >> /etc/hosts\\\"\"" % [
          servers[hostname]["public_ip"],
          hostname,
          servers[hostname]["private_ip"],
          hostname
        ]
        Baker::Log.info( "Setting hostname on %s" % hostname )
        Baker::Log.debug( "CMD: %s" % cmd_set_hostname )
        f_set_hostname.puts( cmd_set_hostname )
        if(options[:dry_run] == false)
          res = `#{cmd_set_hostname}`
          Baker::Log.debug( "Res: %s" % res )
        end
      end

      if(options[:set_acl] == true)
        cmd_set_acl = "knife acl add nodes %s update client %s" % [hostname,hostname]
        Baker::Log.info( "Setting/fixing acl's on %s" % hostname )
        Baker::Log.debug( "CMD: %s" % cmd_set_acl )
        f_set_acl.puts( cmd_set_acl )
        if(options[:dry_run] == false)
          res = `#{cmd_set_acl}`
          Baker::Log.debug( "Res: %s" % res )
        end
      end

      ## @TODO: change this to read the run_list from the config.
      ##  Also, this is clearly a pattern.
      if(options[:set_run_list] == true)
        cmd_set_run_list = "knife node run_list add %s 'role[logstash_%s]'" % [hostname,name.gsub( /-/,'_' )]
        Baker::Log.info( "Setting run_list on %s" % hostname )
        Baker::Log.debug( "CMD: %s" % cmd_set_run_list )
        f_set_run_list.puts( cmd_set_run_list )
        if(options[:dry_run] == false)
          res = `#{cmd_set_run_list}`
          Baker::Log.debug( "Res: %s" % res )
        end
      end

    end
  end

  if(hosts.size > 0)
    f = File.open( "hosts_%s" % name, "w" )
    f.puts(hosts.join( "\n" ))
    f.close
  end

end

if(options[:set_hostname] == true)
  f_set_hostname.close
end

cmd_run_chef = "pssh -h hosts_all -l ubuntu -p 10 -t 0 -x\"-i /home/krogebry/.ssh/keys/aw0_az1_prod0.pem\" \"sudo chef-client -N \\`hostname -f\\`\""
puts cmd_run_chef

if(all_hosts.size > 0)
  f = File.open( "hosts_all","w" )
  f.puts(all_hosts.join( "\n" ))
  f.close
end



