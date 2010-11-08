require 'rubygems'
require 'beanstalk-client'
require 'msgpack'

class StalkTraceInserter

    COMPONENT="StalkInserter"
    VERSION="1.0.0"

    attr_reader :inserted_count

    def initialize( servers, port, debug )
        @debug=debug
        @inserted_count=0
        servers=servers.map {|srv_str| "#{srv_str}:#{port}" }
        debug_info "Starting up, connecting to #{servers.join(' ')}"
        @stalk=Beanstalk::Pool.new servers
        @stalk.use 'untraced'
    end

    def debug_info( str )
        warn "#{COMPONENT} : #{VERSION}: #{str}" if @debug
    end

    def finish
        debug_info "All done!"
        @finished=true
    end

    def finished?
        @finished
    end

    def insert( data, filename, modules )
        debug_info "Inserting new file, size #{data.size/1024}KB"
        debug_info "Whitelisting #{modules}" unless modules.empty?
        pdu={'data'=>data, 'filename'=>filename, 'modules'=>modules}.to_msgpack
        @stalk.put pdu, 65536, 0, 360 # 6 minute TTR
        @inserted_count+=1
    end

end
