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

    def method_missing meth, *args
        @db.send meth, *args
    end

end


module Reductions

    def iterative_reduce( sample )
        minset={}
        coverage=Set.new
        # General Algorithm
        # There are two ways into the minset.
        # 1. Add new blocks
        # 2. Consolidate the blocks of 2 or more existing files
        
        # Not sorted, so can be applied as traces come in
        candidates=sample.to_a.shuffle

        candidates.each {|fn, this_hsh|
            this_set=Set.unpack( this_hsh[:trace] )
            # Do we add new blocks?
            unless (this_set_unique=(this_set - coverage)).empty?
                coverage.merge this_set_unique
                # Any old files with unique blocks that
                # this full set covers can be deleted breakeven at worst
                minset.delete_if {|fn, hsh|
                    hsh[:unique].subset? this_set
                }
                this_hsh[:unique]=this_set_unique
                minset[fn]=this_hsh
            else
                # Do we consolidate 2 or more sets of unique blocks?
                double_covered=minset.select {|fn,hsh|
                    hsh[:unique].subset? this_set
                }
                if double_covered.size > 1
                    merged=Set.new
                    double_covered.each {|fn,hsh|
                        merged.merge hsh[:unique]
                        minset.delete fn
                    }
                    this_hsh[:unique]=merged
                    minset[fn]=this_hsh
                end
            end
        }
        [minset, coverage]
    end

    def greedy_reduce( sample )
        minset={}
        coverage=Set.new
        global_coverage=Set.new
        # General Algorithm:
        # Sort the sets by size
        # Take the best set, strip its blocks from all the others
        # Delete any candidates that are now empty
        # Repeat.

        best_fn, best_hsh=nil,nil
        candidates=sample.dup
        candidates.each {|fn, hsh|
            if best_fn.nil? or Integer( hsh[:covered] ) > Integer(best_hsh[:covered])
                best_fn, best_hsh=fn, hsh
            end
        }
        minset[best_fn]=candidates.delete(best_fn)

        # expand the starter set
        best_set=Set.unpack( best_hsh[:trace] )
        coverage.merge best_set
        global_coverage.merge best_set

        # strip elements from the candidates
        # This is outside the loop so we only have to expand
        # the sets to full size once.
        candidates.each {|fn, hsh|
            this_set=Set.unpack(hsh[:trace])
            global_coverage.merge( this_set )
            hsh[:set]=( this_set - best_set )
        }

        # Now start the reduction loop, the Sets are expanded
        until candidates.empty?
            best_fn, best_hsh=nil,nil
            candidates.each {|fn, hsh|
                if best_fn.nil? or hsh[:set].size > best_hsh[:set].size
                    best_fn, best_hsh=fn, hsh
                end
            }
            minset[best_fn]=candidates.delete(best_fn)
            coverage.merge best_hsh[:set]
            candidates.each {|fn, hsh|
                hsh[:set]=(hsh[:set] - best_hsh[:set])
                candidates.delete( fn ) if hsh[:set].empty?
            }
        end
        raise "Bugger!" unless global_coverage.size==coverage.size
        [minset, coverage]
    end
end

include Reductions
tdb=TraceDB.new OPTS[:file], "re"
full=tdb.sample_fraction(1)
fraction=1/128.0
samples=[]
until fraction > 1 
    samples << tdb.sample_fraction( fraction )
    fraction=fraction*2
end
tdb.close
puts "Collected samples, starting work"
samples.each {|sample|
    puts "Random sample of #{sample.size} from #{full.size}"
    mark=Time.now
    minset, coverage=greedy_reduce( sample )
    puts "Greedy: This sample Minset #{minset.size}, covers #{coverage.size} - #{"%.2f" % (Time.now - mark)} secs"
    mark=Time.now
    minset, coverage=iterative_reduce( sample )
    stage1=Time.now - mark
    puts "Iterative: This sample Minset #{minset.size}, covers #{coverage.size} - #{"%.2f" % stage1} secs"
    mark=Time.now
    minset, coverage=greedy_reduce( minset )
    stage2=Time.now - mark
    puts "Greedy Refined Iterative: This sample Minset #{minset.size}, covers #{coverage.size} - #{"%.2f" % (stage1+stage2)} secs"
}
