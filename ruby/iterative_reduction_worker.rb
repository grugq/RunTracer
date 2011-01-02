# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'trollop'
require File.dirname( __FILE__ ) + '/iterative_reducer'

OPTS=Trollop::options do
    opt :port, "Beanstalk port to connect to", :type=>:integer, :default=>11300
    opt :servers, "Beanstalk servers to connect to", :type=>:strings, :default=>["127.0.0.1"]
    opt :backup_file, "Backup store for the reduced set", :type=>:string, :default=>"ccov-reduced.tch"
    opt :ringbuffer, "Size of ringbuffer for rolling average of added blocks", :type=>:integer, :default=>100
    opt :debug, "Enable debug output", :type=>:boolean
end

reducer_opts={
    :beanstalk_servers=>OPTS[:servers],
    :beanstalk_port=>OPTS[:port],
    :backup_file=>OPTS[:backup_file],
    :ringbuffer=>OPTS[:ringbuffer],
    :debug=>OPTS[:debug]
}

reducer=IterativeReducer.new reducer_opts

trap("INT") { reducer.close; exit }

loop do
    mark=Time.now if OPTS[:debug]
    reducer.process_next
    warn "Elapsed Time: #{Time.now - mark}" if OPTS[:debug]
end
