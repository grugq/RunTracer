# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'trollop'
require File.dirname( __FILE__ ) + '/set_extensions'

OPTS=Trollop::options do
    opt :tracedb, "Trace DB file to use", :type=>:string, :default=>"ccov-traces.tch"
    opt :infile, "File containing filenames of traces to reduce, one per line", :type=>:string
    opt :outfile, "Filename to use for output", :type=>:string
end

class TraceDB

    def initialize( fname, mode )
        @db=OklahomaMixer.open fname, mode
        raise "Err, unexpected size for SetDB" unless @db.size%3==0
    end

    def traces
        @db.size/3
    end

    def close
        @db.close
    end

    def sample_fraction( f )
        raise ArgumentError, "Fraction between 0 and 1" unless 0<f && f<=1
        cursor=(traces * f)-1
        key_suffixes=@db.keys( :prefix=>"trc:" ).shuffle[0..cursor].map {|e| e.split(':').last}.compact
        hsh={}
        key_suffixes.each {|k|
            hsh[k]={
                :covered=>@db["blk:#{k}"],
                :trace=>@db["trc:#{k}"] #still packed.
            }
            raise "DB screwed?" unless hsh[k][:covered] && hsh[k][:trace]
        }
        hsh
    end

    def get_trace( filename )
        hsh={}
        hsh[k]={
            :covered=>@db["blk:#{filename}"],
            :trace=>@db["trc:#{filename}"] #still packed.
        }
        raise "DB screwed?" unless hsh[k][:covered] && hsh[k][:trace]
        }
        hsh
    end

    def method_missing meth, *args
        @db.send meth, *args
    end

end


module Reductions

    DEBUG=false

    def greedy_reduce( sample )
        minset={}
        coverage=Set.new
        global_coverage=Set.new if DEBUG
        # General Algorithm:
        # Sort the candidate sets by size
        # Add the best set to the minset
        # strip its blocks from all the remaining candidates
        # Delete any candidates that are now empty
        # Repeat.

        candidates=sample.dup
        best_fn, best_hsh=candidates.max {|a,b| a[1][:covered].to_i <=> b[1][:covered].to_i }
        minset[best_fn]=candidates.delete(best_fn)

        # expand the starter set
        best_set=Set.unpack( best_hsh[:trace] )
        coverage.merge best_set
        global_coverage.merge best_set if DEBUG

        # strip elements from the candidates
        # This is outside the loop so we only have to expand
        # the sets to full size once.
        candidates.each {|fn, hsh|
            this_set=Set.unpack(hsh[:trace])
            global_coverage.merge( this_set ) if DEBUG
            hsh[:set]=( this_set - best_set )
        }
        candidates.delete_if {|fn,hsh| hsh[:set].empty?}

        # Now start the reduction loop, the Sets are expanded
        until candidates.empty?
            best_fn, best_hsh=candidates.max {|a,b| a[1][:set].size <=> b[1][:set].size }
            minset[best_fn]=candidates.delete(best_fn)
            coverage.merge best_hsh[:set]
            candidates.each {|fn, hsh|
                hsh[:set]=(hsh[:set] - best_hsh[:set])
            }
            candidates.delete_if {|fn,hsh| hsh[:set].empty?}
        end
        if DEBUG && global_coverage.size!=coverage.size
            raise "Missing coverage in greedy reduce!"
        end
        [minset, coverage]
    end
end

include Reductions
tdb=TraceDB.new OPTS[:tracedb], "re"
files=File.open( OPTS[:infile], "rb" ) {|io| io.read}.split("\n")
sample={}
files.each {|fn|
    sample.merge! tdb.get_trace( fn )
}
raise "Barf" unless sample.size==tdb.traces
puts "Greedy reducing #{sample.size} from #{tdb.traces}"
mark=Time.now
minset, coverage=greedy_reduce( sample )
puts "Dumping sample Minset #{minset.size}, covers #{coverage.size} - #{"%.2f" % (Time.now - mark)} secs"
File.open( OPTS[:outfile], "wb+" ) {|ios|
    sample.each {|fn, hsh|
        ios.puts fn
    }
}
