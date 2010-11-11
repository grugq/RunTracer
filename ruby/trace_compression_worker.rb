# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'trollop'
require File.dirname( __FILE__ ) + '/stalk_trace_compressor'

OPTS=Trollop::options do
    opt :beanstalk_port, "Beanstalk port to connect to", :type=>:integer, :default=>11300
    opt :beanstalk_servers, "Beanstalk servers to connect to", :type=>:strings, :default=>["127.0.0.1"]
    opt :lookup_type, "Lookup to use, redis or tc", :type=>:string, :default=>"tc"
    opt :redis_port, "Redis port, for redis", :type=>:integer, :default=>6379
    opt :redis_server, "Redis server, for redis", :type=>:string, :default=>"127.0.0.1"
    opt :lookup_file, "Use existing lookup file, for tc", :type=>:string, :default=>"ccov-lookup.tch"
    opt :debug, "Enable debug output", :type=>:boolean
end

compressor_opts={
    :beanstalk_servers=>OPTS[:beanstalk_servers],
    :beanstalk_port=>OPTS[:beanstalk_port],
    :redis_server=>OPTS[:redis_server],
    :redis_port=>OPTS[:redis_port],
    :lookup_type=>OPTS[:lookup_type].to_sym,
    :lookup_file=>OPTS[:lookup_file],
    :debug=>OPTS[:debug]
}

compressor=StalkTraceCompressor.new compressor_opts

trap("INT") { compressor.close_database; exit }

loop do
    compressor.compress_next
end
