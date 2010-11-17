# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require File.dirname(__FILE__) + "/word_tracer"

# Mainly test code.

begin
ARGV.each {|fn|
    begin
        mark=Time.now
        w=WordTracer.new fn
        result=w.trace
        puts "Baddabing baddaboom, #{fn} - #{result} after #{Time.now - mark} secs."
        File.open( "trace.out", "rb") {|ios|
            puts "Tracefile has #{(lines=ios.readlines).size} unique edges."
            this=[]
            lines.each {|l|
                from,to,count=l.split
                this.push "#{from}-#{to}".to_sym
            }
            @totalcov||=[]
            puts "This file added #{(this - @totalcov).size} edges" 
            @totalcov=(@totalcov | this)
        }
        w.sweep
        w.close
    rescue
        raise $!
    ensure
        w.close rescue nil
    end
    puts "So far #{@totalcov.size} edges."
}
rescue
    puts $!
    puts $@
end
