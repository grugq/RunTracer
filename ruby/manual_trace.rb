require File.dirname(__FILE__) + "/word_tracer"

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
