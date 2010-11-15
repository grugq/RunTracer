# Author: Ben Nagy
# Copyright: Copyright (c) Ben Nagy, 2006-2010.
# License: The MIT License
# (See README.TXT or http://www.opensource.org/licenses/mit-license.php for details.)

class IterPi

    MD5MAX=340282366920938463463374607431768211455.0

    def initialize
        @inside,@total=0.0,0.0
        @coords=[]
    end

    def update( md5sum )
        @coords << (md5sum.to_i(16) / MD5MAX)
        if @coords.length==2
            @inside+=1 if (Math::hypot(*@coords) < 1)
            @total+=1
            @coords.clear
        end
    end

    def pi
        @inside * 4 / @total
    end

end
