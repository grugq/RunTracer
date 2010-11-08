require 'rubygems'
require 'beanstalk-client'
require 'msgpack'

class Store < Hash
    # Placeholder for a KV store
end

class StalkTraceProcessor

    COMPONENT="StalkTraceProcessor"
    VERSION="1.0.0"

    attr_reader :processed_count

    def initialize( servers, port, work_dir, debug, old_store=nil )
        @work_dir=work_dir
        @debug=debug
        servers=servers.map {|srv_str| "#{srv_str}:#{port}" }
        debug_info "Starting up, connecting to #{servers.join(' ')}"
        setup_store( old_store )
        @processed_count=0
        @stalk=Beanstalk::Pool.new servers
        @stalk.watch 'traced'
    end

    def setup_store( old_store )
        if old_store
            # read files or whatever
        else
            @minset=Store.new
            @lookup=Store.new
            @lookup['idx']=0
            @totalcov=Set.new
        end
    end

    def deflate( set )
        set.map! {|elem|
            unless @lookup.has_key? elem
                new_idx=(@lookup['idx']+=1)
                @lookup.store elem, new_idx
                @lookup.store new_idx, elem
            end
            @lookup.fetch elem
        }
    end

    def inflate( set )
        # fetch raises if the key isn't present
        set.map {|elem| @lookup.fetch elem}
    end

    def debug_info( str )
        warn "#{COMPONENT} : #{VERSION}: #{str}" if @debug
    end

    def create_set( output )
        lines=output.split("\n")
        this_trace=Set.new
        lines.each {|l|
            from,to,count=l.split
            from="NOMODULE" if from[0]=='?'
            to="NOMODULE" if to[0]=='?'
            this_trace.add "#{from}=>#{to}".to_sym
        }
        deflated=deflate this_trace
    end

    def update_minset( result, trace_output, filename )

        # Create a set from the trace (also deflates edges to indicies)
        this_trace=create_set( trace_output )
        debug_info "#{result} for #{filename} - trace has #{this_trace.size} unique edges, was #{trace_output.split("\n").size}"

        # Merge this trace into the total coverage, and see
        # if it added any edges.
        tcbefore=@totalcov.size
        mark=Time.now
            @totalcov.merge this_trace
        debug_info "Took #{Time.now - mark} for merge into totalcov."
        tcafter=@totalcov.size
        debug_info "Check: #{@lookup.size / 2} in lookup #{tcafter} in totalcov"
        if tcbefore==tcafter
            debug_info "No new edges from this trace"
        else
            debug_info "this trace added #{tcafter - tcbefore} edges" 
        end

        # Delete any traces in the minset which are subsets of this trace
        msbefore=@minset.size
        mark=Time.now
            @minset.delete_if {|fname, set| 
                set.proper_subset? this_trace
            }
        debug_info "took #{Time.now - mark} for subset check..."

        # Store this trace in the minset if it added edges, or should now
        # one or more sets in the minset (which were just deleted)
        if tcafter > tcbefore or @minset.size < msbefore
            @minset.store filename, this_trace
        end

        debug_info "Now we have #{@minset.size} files covering #{tcafter} edges."
    end

    def process_next
        debug_info "getting next trace"
        job=@stalk.reserve # from 'traced' tube
        pdu=MessagePack.unpack( job.body )
        update_minset( pdu['result'], pdu['trace_output'], pdu['filename'] )
        job.delete
        @processed_count+=1
    rescue
        raise $!
    end

end
