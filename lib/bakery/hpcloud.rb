##
# HPCloud bits.

module Bakery
  module HPCloud

    class Session
      def initialize()
        @fs_session_file = "%s/tmp/hpcloud-session.json" % FS_ROOT
        Bakery::Log.debug( "Session: %s" % @fs_session_file )

        if(!File.exists?( @fs_session_file ))
          Bakery::Log.debug( "Session file does not exist" )
          @session = self.get_session() 

        else
          @session = JSON::parse(File.read( @fs_session_file ))
          t = Time.parse( @session["access"]["token"]["expires"] )
          Bakery::Log.debug( "Session expires in: %s seconds" % (t - Time.new).to_i )

          @session = self.get_session() if((t - Time.new).to_i < 0) ## It's expired, get a new one.
        end
      end

      def get_session()
        Bakery::Log.debug( "Getting session from auth end point" )

        auth_cfg = YAML.load(File.read( "%s/.hpcloud/accounts/hp" % ENV['HOME'] ))
        #auth_uri = URI.parse( "https://region-a.geo-1.identity.hpcloudsvc.com:35357/v2.0/tokens" )
        #auth_uri = URI.parse(Bakery::Config::cloud_url)
        auth_uri = URI.parse( CLOUD_URL )
        Bakery::Log.debug( "Auth: %s/%s" % [auth_uri.host,auth_uri.port] )

        auth_http = Net::HTTP.new( auth_uri.host,auth_uri.port )
        auth_http.use_ssl = true
        auth_http.verify_mode = OpenSSL::SSL::VERIFY_NONE

        res = auth_http.post( auth_uri.path, {
          "auth" => {
            "apiAccessKeyCredentials" => {
              "accessKey" => auth_cfg[:credentials][:account_id],
              "secretKey" => auth_cfg[:credentials][:secret_key]
            },
            "tenantId" => auth_cfg[:credentials][:tenant_id]
          }
        }.to_json, { "Content-Type" => "application/json" })

        if(res.code.to_i == 200)
          f = File.open( @fs_session_file, "w" )
          f.puts( res.body )
          f.close
        end

        return JSON::parse( res.body )
      end ## get_session

      def get_service_catalog( catalog_name )
        @session["access"]["serviceCatalog"].select{|hsh| hsh["name"] == catalog_name }.first
      end

      def cache_hit( key,flush_cache=false )
        #Bakery::Log.debug( "Cache key: %s" % key )
        fs_cache_file = "%s/tmp/cache/%s" % [FS_ROOT, key]

        if(!File.exists?( fs_cache_file ) || flush_cache == true)
          data = yield
          #Bakery::Log.debug( "Opening: %s" % fs_cache_file )
          f = File.open( fs_cache_file, "w" )
          f.puts( data.to_json )
          f.close
          #Bakery::Log.debug( "Closing: %s" % fs_cache_file )

        else
          data = JSON::parse(File.read( fs_cache_file ))

        end
        #Bakery::Log.debug( "Returning: %s" % data )
        return data
      end

      def do_request( uri )
        http = Net::HTTP.new( uri.host,uri.port )

        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE

        headers = {
          "Content-Type" => "application/json",
          "X-Auth-Token" => @session["access"]["token"]["id"]
        }

        ts_start = Time.new.to_f()
        res = yield( http, headers )
        runtime = (Time.new.to_f() - ts_start)
        Bakery::Log.debug( "Runtime: %.2f" % runtime )
        if(res.code.to_i == 200 || res.code.to_i == 202)
          return JSON::parse( res.body ) 
        else
          Bakery::Log.debug( "Failied: %i" % res.code.to_i )
          Bakery::Log.debug( res.body )
        end
      end

      def get_rest( url )
        uri = URI.parse( url )
        #Bakery::Log.debug( "URL: %s" % url )
        return do_request( uri ) do |http, headers|
          http.get( uri.path, headers )
        end
      end

      def post_rest( url,data )
        uri = URI.parse( url )
        Bakery::Log.debug( "Posting to: %s" % url )
        Bakery::Log.debug( "Data: %s" % data )
        http = Net::HTTP.new( uri.host,uri.port )
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        headers = {
          "Content-Type" => "application/json",
          "X-Auth-Token" => @session["access"]["token"]["id"]
        }
        #Bakery::Log.debug( "Headers: %s" % headers.inspect )
        res = http.post( url,data, headers )
        if(res.code.to_i == 200 || res.code.to_i == 202)
          return JSON::parse( res.body ) 
        else
          Bakery::Log.debug( "Failied: %i" % res.code.to_i )
          Bakery::Log.debug( res.body )
        end
      end

      def get_catalog_url( cat_name,region_name )
        cat = get_service_catalog( cat_name )
        #Bakery::Log.debug( "Cat: %s" % cat.inspect )
        region = cat["endpoints"].select{|cat| cat["region"] == region_name }.first

        #Bakery::Log.debug( "Region: %s" % region.inspect )
        pub_url = region["publicURL"]

        #Bakery::Log.debug( "PubUrl: %s" % pub_url )
        return pub_url
      end

      def get_servers( region_name,flush_cache=false )
        cache_key = "%s-servers" % region_name
        pub_url = get_catalog_url( "Compute",region_name )
        cache_hit( cache_key,flush_cache ) do 
          get_rest( "%s/servers" % pub_url )
        end
      end

      def create_server( srv, region_name )
        pub_url = get_catalog_url( "Compute",region_name )
        post_rest( "%s/servers" % pub_url, { "server" => srv }.to_json )  
      end

      def get_keys()
      end

      def create_keypair( key_name, region_name )
        pub_url = get_catalog_url( "Compute",region_name )
        post_rest( "%s/os-keypairs" % pub_url, { "keypair" => { "name" => key_name, "public_key" => ADMIN_KEYS }}.to_json )  
      end

    end ## Session

  end ## HPCloud
end ## Bakery
