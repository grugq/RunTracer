# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'trollop'
require File.dirname( __FILE__ ) + '/trace_codec'
require File.dirname( __FILE__ ) + '/set_extensions'

OPTS=Trollop::options do
    opt :file, "Trace DB file to use", :type=>:string, :default=>"ccov-traces.tch"
end

class TraceDB

    def initialize( fname, mode )
        @db=OklahomaMixer.open fname, mode
        raise "Err, unexpected size for SetDB" unless @db.size%3==0
    end

    def traces
        @db.size/3
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

end

tdb=TraceDB.new OPTS[:file], "re"
full=tdb.sample_fraction(1)

def greedy_reduce( set_hash )
    puts "Starting sample with #{set_hash.size} sets"
    candidates=set_hash.sort_by {|k,v| Integer( v[:covered] ) }
    minset=[]
    coverage=Set.new
    global_coverage=Set.new
    best_fn, best_hsh=candidates.pop
    minset.push best_fn

    # expand the starter set
    best_set=Set.unpack( best_hsh[:trace] )
    coverage=coverage.union( best_set )
    global_coverage=global_coverage.union( best_set )
    puts "Initial best set #{coverage.size} elems"

    # strip elements from the candidates
    # This is outside the loop so we only have to expand
    # the sets to full size once.
    candidates.each {|fn, hsh|
        this_set=Set.unpack( hsh[:trace] )
        global_coverage=global_coverage.union( this_set )
        hsh[:set]=(this_set - best_set)
    }
    candidates.delete_if {|fn, hsh| hsh[:set].empty? }
    candidates=candidates.sort_by {|fn, hsh| hsh[:set].size }
    best_fn, best_hsh=candidates.pop
    minset.push best_fn
    best_set=best_hsh[:set]
    puts "Next best has #{best_set.size} elems left"
    coverage=coverage.union( best_set )

    # Now start the reduction loop, the Sets are expanded
    puts "Starting reduction"
    until candidates.empty?
        candidates.each {|fn, hsh|
            this_set=hsh[:set]
            hsh[:set]=(this_set - best_set)
        }
        candidates.delete_if {|fn, hsh| hsh[:set].empty? }
        candidates=candidates.sort_by {|fn, hsh| hsh[:set].size }
        best_fn, best_hsh=candidates.pop
        minset.push best_fn
        best_set=best_hsh[:set]
        coverage=coverage.union( best_set )
    end
    raise "Bugger." unless coverage.size==global_coverage.size
    [minset, coverage]
end

fraction=0.125
until fraction==1 
    this_sample=tdb.sample_fraction fraction
    puts "FULL: #{full.size} THIS: #{this_sample.size}"
    minset, coverage=greedy_reduce( this_sample )
    puts "This sample Minset #{minset.size}, covers #{coverage.size}"
    fraction=fraction*2
end
