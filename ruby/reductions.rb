# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require File.dirname( __FILE__ ) + '/set_extensions'

module Reductions

    DEBUG=false

    def iterative_reduce( sample )
        minset={}
        coverage=Set.new
        global_coverage=Set.new if DEBUG
        # General Algorithm
        # There are two ways into the minset.
        # 1. Add new blocks
        # 2. Consolidate the blocks of 2 or more existing files

        sample.each {|fn, this_hsh|
            this_set=Set.unpack( this_hsh[:trace] )
            global_coverage.merge this_set if DEBUG
            unless this_set.subset? coverage
                # Do we add new blocks?
                this_set_unique=(this_set - coverage)
                coverage.merge this_set_unique
                # Any old files with unique blocks that
                # are covered by this set can be deleted 
                # and their unique blocks merged with those of this set
                # (this is breakeven at worst)
                minset.delete_if {|fn, hsh|
                    this_set_unique.merge( hsh[:unique] ) if hsh[:unique].subset?( this_set ) 
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
        #double check
        if DEBUG && global_coverage.size!=coverage.size
            raise "Missing coverage in iterative reduce!"
        end
        [minset, coverage]
    end

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
