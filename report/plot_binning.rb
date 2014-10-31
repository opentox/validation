# #!/usr/bin/env ruby
#require "./config.rb"
#require "bundler"
#Bundler.require
#d = YAML.load(OpenTox::RestClientWapper.get("http://localhost:8087/validation/crossvalidation/64/prediction_data"))

class Prediction
  attr_accessor :conf, :act, :pred
end

class Array
  def accuracy
    correct = 0
    self.size.times do |i|
      correct += 1 if self[i].pred==self[i].act
    end
    return correct/self.size.to_f
  end
end

class Float
  def round3
    (self*1000.0).round/1000.0
  end
end

module Reports
  
  module PlotBinning
    
    private
    MIN_NUM_COMPOUNDS_PER_BIN = 12
    MAX_NUM_BINS = 10

    def self.predictions(conf_vals, pred_vals, act_vals)
      predictions = []
      conf_vals.size.times.each do |i|
        p = Prediction.new
        p.conf = conf_vals[i]
        p.pred = pred_vals[i]
        p.act = act_vals[i]
        predictions << p if p.conf!=nil and p.pred!=nil and p.act!=nil
      end
      predictions
    end

    def self.equal_frequency_binning(predicitons)
      #TODO fix binning
      #last bin may be too small
      #eqal confidence values may screw things up
      num = [MIN_NUM_COMPOUNDS_PER_BIN,predictions.length/MAX_NUM_BINS].max
      split = []
      tmp = []
      predictions.each_with_index do |p,i|
        if tmp.length>=num and tmp[-1].conf!=p.conf
          split << tmp
          tmp = []
        end
        tmp << p
      end
      split << tmp
      $logger.debug "#{split.size}: #{split.collect{|e| e.size}}"
      split
    end

    def self.equal_width_binning(predictions)
      min_split_size = nil
      num_splits = MAX_NUM_BINS
      max_conf = predictions.first.conf
      min_conf = predictions.last.conf
      delta_conf = max_conf-min_conf
      
      while min_split_size==nil || min_split_size<MIN_NUM_COMPOUNDS_PER_BIN
        
        $logger.debug "#{split.size}: #{split.collect{|e| e.size}}" if defined?(split) and split
        preds = predictions
        step = (max_conf-min_conf)/num_splits.to_f
        min_split_size = nil
        split = []
        num_splits.times do |i|
          tmp = []
          preds.each do |p|
            tmp << p if p.conf>=max_conf-step*(i+1)
          end
          preds -= tmp
          min_split_size=tmp.size if min_split_size==nil or tmp.size<min_split_size
          split << tmp
        end
        raise "#{preds.size} #{preds}" unless preds.size==0
        
        num_splits -= 1
      end
      $logger.debug "#{split.size}: #{split.collect{|e| e.size}}"
      split
    end

    def self.split_to_bins(split)
      bins = []
      split.size.times do |i|
        bins << [ (i==0 ? split[i].first.conf.round3 : ((split[i-1].last.conf+split[i].first.conf)/2).round3),
                  (i==split.size-1 ? split[i].last.conf.round3 : ((split[i].last.conf+split[i+1].first.conf)/2).round3),
                  split[i].accuracy.round3 ]
      end
      bins
    end

    public
    def self.plot( conf_vals, pred_vals, act_vals )
      preds = predictions(conf_vals, pred_vals, act_vals)
      split = equal_width_binning(preds)
      bins = split_to_bins(split)
      title = "Equal+width+binning"
      $logger.debug bins.inspect
      File.join($validation[:uri],"binplot/#{bins.collect{|bin| bin.join(",")}.join(";")}?title=#{title}&xlab=confidence&ylab=accuracy")
    end

    def self.demo
      unless defined?($logger)
        require "logger"
        $logger = Logger.new(STDOUT)
      end
      $validation = {:uri => "http://localhost:8087/validation"} unless $validation
      confidence_values = [ 0.6624125079426938, 0.6557249417249419, 0.644986726236726, 0.6063058457707288, 0.5953180153180153, 0.5938923422256757, 0.5902730212930881, 0.5878446553446554, 0.5726630326195544, 0.570767093745035, 0.570767093745035, 0.5687276491624317, 0.5607772946008241, 0.5587703350570997, 0.5555555555555555, 0.5429030444603734, 0.5424604381126121, 0.5410762032085562, 0.5295781902373767, 0.5268088994718326, 0.5045040743570155, 0.502212185697837, 0.5, 0.4800000000000001, 0.45748788248788247, 0.44985470725855337, 0.4450265643447462, 0.4303489858095122, 0.4241671534924129, 0.4172702297702297, 0.4133333333333333, 0.4, 0.375, 0.36765717942188536, 0.3611111111111111, 0.35564143458880304, 0.34989367357788415, 0.3390269151138717, 0.33746495050842873, 0.33701194638694637, 0.3333333333333333, 0.3333333333333333, 0.3330026455026455, 0.3259307359307359, 0.3249608051869459, 0.3165650536247021, 0.3157291149078215, 0.3156934568699275, 0.2962364033397402, 0.2909536337845161, 0.2807823129251701, 0.2569325177872053, 0.2548106212763212, 0.25364933434501535, 0.2523809523809524, 0.24373406774354797, 0.22782241912676693, 0.2027758130504126, 0.1934155112173688, 0.18392695429862332, 0.16695652173913045, 0.1430643962390448, 0.14084600861095425, 0.06619047619047619, 0.06531746031746032, 0.05716999050332382, 0.045232988309847594, 0.005059523809523819, 0.0025123685837971483, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 ]
      predicted_values = [ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 1, 0, 0, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil ]
      actual_values = [ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1 ]
      puts plot(confidence_values, predicted_values, actual_values )
    end

  end
end



