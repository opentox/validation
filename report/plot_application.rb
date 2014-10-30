require 'digest/md5'

class Validation::Application < OpenTox::Application

  helpers do
    def eval_r(r, cmd)
      $logger.debug cmd
      r.eval cmd
    end
  end

  # produces a boxplot
  # params should be given in URI, e.g. : ..boxplot/test_values=5.8,5.6,5.3;predicted=5.9
  # ; separates series (or categories)
  # = seperates key and values for each series
  # , seperates values for each series
  # 'hline=<float>' can be given as optional param (with '?') to draw horizontal lines with the given stepwidth
  # (default: no horizontal lines, lines allow to compare different plots)
  get '/validation/boxplot/:vals' do

    filename = "#{Digest::MD5.hexdigest(params[:vals].inspect+params[:hline].inspect+params[:size].inspect)}.png"
    unless (File.exists?("/tmp/#{filename}"))
      # retrieve values
      vals = {}
      params[:vals].split(";").collect do |x|
          y = x.split("=")
          vals[y[0]] = (y[1] ? y[1].split(",").collect{|z| z.to_f} : nil)
      end
      names = "c(\""+vals.keys.join("\",\"")+"\")"
      values = vals.values.collect{|a| "c("+(a ? a.join(",") : "")+")"}.join(",")
      
      # the min range is set to hline*2 to draw at least two horizontal lines
      hline = params[:hline] ? params[:hline].to_f : nil
      unless hline
        ylim = ""
      else
        min = vals.values.flatten.compact.min
        max = vals.values.flatten.compact.max
        if (max-min<(hline*2))
          to_add = (hline*2)-(max-min)
          min -= to_add/2.0
          max += to_add/2.0
        end
        range = "c(#{min},#{max})"
        ylim = ",ylim=#{range}"
      end

      # return "boxplot(#{values},col=c('red','blue','green'),names=#{names}#{ylim})"
      @r = RinRuby.new(true,false)
      size = (params[:size] ? params[:size].to_i : 300)
      eval_r(@r,"png(\"/tmp/#{filename}\",width=#{2*size},height=#{size})")
      eval_r(@r,"par(mai=c(0.5,0.5,0.2,0.2))")
      eval_r(@r,"boxplot(#{values},col=c('red','blue','green'),names=#{names}#{ylim})")
      if hline
        # seq defines were to draw hline
        # example: min -9.5, max 10.5, hline = 2 -> seq(-10,12,by=2) -> produces lines from -10 to 12 with step-width 2
        eval_r(@r,"abline(h=seq(floor(#{min}/#{hline})*#{hline}, round(#{max}/#{hline})*#{hline}, by=#{hline}),lty=2,col='dimgrey')")
      end
      eval_r(@r,'dev.off()')
      @r.quit
    end
    send_file("/tmp/#{filename}",:filename=>"#{params[:vals]}.png",:type=>'image/png',:disposition => 'inline')
  end

  get '/validation/binplot/:vals' do

    filename = "#{Digest::MD5.hexdigest(params[:vals].inspect+params[:size].inspect)}.png"
    unless (File.exists?("/tmp/#{filename}")) and false

      @r = RinRuby.new(true,false)
      size = (params[:size] ? params[:size].to_i : 300)

      # each bin is given as x1,x2,y
      xvals = []
      yvals = []
      params[:vals].split(";").each do |bin|
        x1,x2,y = bin.split(",")
        if xvals.size==0 # first add point at y=0 to add a vertrical line from 0 to x1
          xvals << x1.to_f
          yvals << 0
        end
        # for each bin, add an additional point at y=0 to draw a vertrical line to 0
        xvals += [x1.to_f, x2.to_f, x2.to_f]
        yvals += [y.to_f,  y.to_f, 0]
      end
      # add first point again to draw horizontal line at y=0
      xvals << xvals[0]
      yvals << yvals[0]

      eval_r(@r,"x <- c(#{xvals.join(",")})")
      eval_r(@r,"y <- c(#{yvals.join(",")})")
      eval_r(@r,"png(\"/tmp/#{filename}\",width=#{2*size},height=#{size})")
#      eval_r(@r,"par(mai=c(0.5,0.5,0.2,0.2))")
#      eval_r(@r,"par(mfrow=c(2,4))")
      eval_r(@r,"plot(x,y,type='n', xlim=rev(range(x)), ylim=c(0,max(y)), xlab='#{params[:xlab]}', ylab='#{params[:ylab]}')")# type='n',
#      eval_r(@r,"par(pch=22, col='red')")
      eval_r(@r,"lines(x,y, type='l', col='red')")
      eval_r(@r,"title(main='#{params[:title]}')")
      eval_r(@r,'dev.off()')
      @r.quit
    end
    send_file("/tmp/#{filename}",:filename=>"#{params[:vals]}.png",:type=>'image/png',:disposition => 'inline')
  end

end
