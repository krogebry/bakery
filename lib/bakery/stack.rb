##
# Stack!

module Bakery
  class Stack

    @cfg
    @hpcloud
    @zone_cfg
    @zone_name
    attr_accessor :cfg

    def initialize( cfg )
      #Bakery::Log.debug( "Cfg: %s" % cfg );
      @cfg = cfg
      @hpcloud = Bakery::HPCloud::Session.new()
      @zone_cfg = cfg["zone"]
      @zone_name = cfg["zone_name"]
      #Bakery::Log.debug( "Cfg: %s" % cfg )
    end

    def create_resource( cfg )
      #pp cfg
      srv = {
        "flavorRef" => cfg["flavor_id"],
        "imageRef" => cfg["image_id"],
        "key_name" => "%s.%s" % [@zone_name,DOMAIN_NAME],
        "name" => cfg["hostname"]
        #"security_groups" => {
          #"name" => "default"
        #}
      }
      #pp srv
      @hpcloud.create_server( srv, @zone_cfg["region_name"] )
    end

    def check_cloud( chef_srv )
      server_names = @hpcloud.get_servers( @zone_cfg["region_name"],true )["servers"].map{|s| s["name"] }
      @cfg["resources"].each do |name,cfg|
        res_name = "%s-%s" % [@cfg["name"],name]
        Bakery::Log.info( "Resource: %s" % res_name )
        cfg["min"].times do |host_id|
          hostname = ("%s%i.%s.%s" % [res_name, host_id, @zone_name, DOMAIN_NAME]).gsub( /_/,'-' )
          if(!server_names.include?( hostname ))
            Bakery::Log.debug( "Does not exist: %s" % hostname )
            create_resource(cfg.merge({ "hostname" => hostname }))

          else
            Bakery::Log.debug( "Exists: %s" % hostname )
            begin
              node = JSON::parse(chef_srv.get_rest( "/nodes/%s" % hostname ).to_json)
            rescue Net::HTTPServerException => e
              next
            end

            chef_run_list = (cfg.has_key?( "chef" ) && cfg["chef"].has_key?( "run_list" ) && cfg["chef"]["run_list"] != nil ? cfg["chef"]["run_list"] : [])
            node["run_list"] = chef_run_list
            chef_tags = (cfg.has_key?( "chef" ) && cfg["chef"].has_key?( "tags" ) && cfg["chef"]["tags"] != nil ? cfg["chef"]["tags"] : [])
            node["normal"]["tags"] = chef_tags

            ## Enforce the chef_env bits
            if(node["chef_environment"] == "_default")
              node["chef_environment"] = "prod"
            end

            Bakery::Log.debug( "Tags: %s" % node["normal"]["tags"].inspect )
            Bakery::Log.debug( "ChefEnv: %s" % node["chef_environment"] )
            Bakery::Log.debug( "Runlist: %s" % node["run_list"].inspect )

            #if(options[:dry_run] == false)
              Bakery::Log.debug( "Updating node: %s" % hostname )
              chef_srv.put_rest( "/nodes/%s" % hostname, node )
            #end
          end ## included
        end ## times
      end ## resources
    end ## check_cloud

  end ## Stack
end ## Bakery
