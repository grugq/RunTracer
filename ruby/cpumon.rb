# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

require 'rubygems'
require 'windows/time'
require 'win32/process'

class ProcessCPUMonitor

    include Windows::Process
    include Windows::Error
    include Windows::Window
    include Windows::Handle
    include Windows::Time

    COMPONENT="ProcessCPUMonitor"
    VERSION="1.0.0"

    def raise_win32_error 
        unless (err_code=GetLastError.call)==ERROR_SUCCESS 
            msg = ' ' * 255 
            msgLength = FormatMessage.call(0x3000, 0, err_code, 0, msg, 255, '') 
            msg.gsub!(/\000/, '').strip! 
            raise "#{COMPONENT}:#{VERSION}: Win32 Exception: #{msg}" 
        else 
            raise 'GetLastError returned ERROR_SUCCESS' 
        end 
    end 

    def initialize( pid, thresh, nper=15, len=1 )
        @pid,@thresh,@nper,@len=pid, thresh, nper, len
    end

    def less_than_threshold?
        # Blocks for nper * len seconds (give or take, sleep is not exact)
        # Just returns a boolean
        begin
            raise_win32_error if (hProcess=OpenProcess.call(PROCESS_QUERY_INFORMATION, 0, @pid )).zero?
            percents=[]
            @nper.times do
                proc_k_then, proc_u_then, sys_k_then, sys_u_then = get_times( hProcess )
                sleep @len
                proc_k_now, proc_u_now, sys_k_now, sys_u_now = get_times( hProcess )
                proc_total_diff = (proc_u_now - proc_u_then + proc_k_now - proc_k_then)
                sys_total_diff = (sys_u_now - sys_u_then + sys_k_now - sys_k_then)
                percents << (proc_total_diff.to_f / sys_total_diff.to_f)*100
            end
            average=percents.inject {|s,n| s+=n} / percents.size
        rescue
            raise $!
        ensure
            CloseHandle.call( hProcess )
        end
        average < @thresh
    end

    def get_times( hProcess )
        # Return the current kernel and user times for the system and the specified hProcess
        # Uses a ghetto version of a FILETIME struct, which is converted into a quadword.
        create_time,exit_time,ktime,utime=[0].pack('Q'),[0].pack('Q'),[0].pack('Q'),[0].pack('Q')
        raise_win32_error if (GetProcessTimes.call( hProcess, create_time, exit_time, ktime, utime )).zero?
        sys_itime,sys_ktime,sys_utime=[0].pack('Q'),[0].pack('Q'),[0].pack('Q'),[0].pack('Q')
        raise_win32_error if (GetSystemTimes.call( sys_itime, sys_ktime, sys_utime )).zero?
        [ktime.unpack('Q').first, utime.unpack('Q').first, sys_ktime.unpack('Q').first, sys_utime.unpack('Q').first] 
    end
end
