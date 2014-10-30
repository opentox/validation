require "./lib/prediction_data.rb"
require "./lib/predictions.rb"

module Lib
  
  class OTPredictions < Predictions

    attr_reader :training_values, :prediction_feature_title
    
    def initialize(data, compounds=nil, training_values=nil, prediction_feature_title=nil)
      internal_server_error unless data.is_a?(Hash)
      super(data)
      @compounds = compounds
      @training_values = training_values
      @prediction_feature_title = prediction_feature_title
    end
    
    def identifier(instance_index)
      compound(instance_index)
    end
  
    def compound(instance_index)
      @compounds[instance_index]
    end

    def compute_stats()
      res = {}
      case feature_type
      when "classification"
        (Validation::VAL_CLASS_PROPS).each{ |s| res[s] = send(s)}  
      when "regression"
        (Validation::VAL_REGR_PROPS).each{ |s| res[s] = send(s) }  
      end
      return res
    end
    
    def to_array()
      OTPredictions.to_array( [self] )
    end

    def self.to_array( predictions, format=false, validation_uris=nil )
  
      confidence_available = false
      training_data_available = false
      predictions.each do |p|
        confidence_available |= p.confidence_values_available?
        training_data_available |= p.training_values.keys.flatten.size>0
      end

      res = []
      count = 0
      join_map = {}
      predictions.each do |p|
        v_uris = validation_uris[count] if validation_uris
        count += 1
        p.num_instances.times do |i|
          a = {}
          a["Compound"] = p.identifier(i)+"?media=image/png&size=150"
          a["Compound URI"] = p.identifier(i)
          a["Training value"] = p.training_values[p.identifier(i)] if training_data_available
          a["Test value"] = p.actual_value(i)
          a["Predicted value"] = p.predicted_value(i)
          if p.feature_type=="classification"
            if (p.predicted_value(i)!=nil and p.actual_value(i)!=nil)
              if p.classification_miss?(i)
                a["Classification"] = (format ? ICON_ERROR : 1)
              else
                a["Classification"] = (format ? ICON_OK : 0)
              end
            end
          else
            if (p.predicted_value(i)!=nil and p.actual_value(i)!=nil)
              a["Error"] = (p.actual_value(i)-p.predicted_value(i)).abs
            end
          end
          a["Confidence value"] = p.confidence_value(i) if confidence_available
          a["Validation URI"] = v_uris[i] if validation_uris

          idx = join_map["#{p.identifier(i)}#{v_uris ? v_uris[i] : ''}"]
          if (idx!=nil and format) # join equal compounds unless formatting is disabled
            raise "prediciton of same compound in same validation should be equal" unless res[idx]["Predicted value"]==a["Predicted value"]
            ["Error", "Test value" ].each do |v|
              res[idx][v] = [ res[idx][v], a[v] ].flatten.compact if res[idx].has_key?(v) or a.has_key?(v)
            end
            res[idx]["Classification"]=nil if a["Classification"] and res[idx]["Classification"]!=a["Classification"]
          else
            join_map["#{p.identifier(i)}#{v_uris ? v_uris[i] : ''}"] = res.size
            res << a
          end
        end
      end

      unless predictions.first.feature_type=="classification"
        # compute horziontal line step-width to make boxplots inter-comparable
        # step 1: compute max delta
        delta = 0
        res.each do |r|
          vals = ["Training value","Predicted value","Test value"].collect{|k| r[k]==nil ? [] : r[k] }.flatten
          delta = [delta,(vals.max-vals.min)].max if vals.size>0
        end
        # step 2: compute stepwidth by rounding off to power of 10
        # e.g. delta > 100 -> stepwidth = 100, delta within [10-99.9] -> stepwidth = 10, delta within [1-9.99] -> stepwidth = 1
        hline = 10**Math.log(delta,10).floor
      end

      transformer = PredictionTransformer.new(res.collect{|r| r["Compound URI"]},predictions.first.prediction_feature_title)

      res.size.times do |r|
        # add boxplot
        unless predictions.first.feature_type=="classification"
          # add boxplots including training, test and predicted values
          val_str = training_data_available ? "training=#{[res[r]["Training value"]].join(",")};" : ""
          val_str << "test=#{[res[r]["Test value"]].join(",")};predicted=#{[res[r]["Predicted value"]].join(",")}"
          res[r]["Boxplot"] = File.join($validation[:uri],"/boxplot/#{val_str}?hline=#{hline}&size=150")
        end
        # render missing values
        if format
          res[r]["Test value"] = "'missing'" unless res[r]["Test value"]
          res[r]["Predicted value"] = (res[r]["Training value"] ? "'in-training-data'" : "'outside-AD'") unless res[r]["Predicted value"]
        end
        # handle arrays
        # add transformed values
        ["Training value","Test value","Predicted value","Error","Confidence value","Validation URI"].each do |v|
          next unless res[r].has_key?(v)
          vals = [res[r][v]].flatten
          do_transform = (transformer.do_transform? and ["Training value","Test value","Predicted value"].include?(v))
          if predictions.first.feature_type=="classification" or vals.any?{|x| !x.is_a?(Numeric)}
            res[r][v] = vals.join(", ")
          elsif vals.size==1
            res[r][v] = vals.first.to_nice_s
            res[r][v] += "\n#{transformer.transform(vals.first,res[r]["Compound URI"])}" if do_transform
          else # vals.size > 1
            mean = vals.inject(0.0) { |sum, el| sum + el } / vals.size
            res[r][v] = "#{mean.to_nice_s} (mean)"
            res[r][v] += "\n#{transformer.transform(mean,res[r]["Compound URI"])}" if do_transform
            res[r][v] += "\n("+vals.collect{|v| v.to_nice_s}.join(", ")
            res[r][v] += "\n#{transformer.transform(vals,res[r]["Compound URI"])}" if do_transform
            res[r][v] += ")"
          end
        end
      end

      header = []
      header << "Compound" if format
      header << "Training value" if training_data_available
      header << "Test value"
      header << "Predicted value"
      if predictions.first.feature_type=="classification"
        header << "Classification" 
      else 
        header << "Error"
        header << "Boxplot"
      end
      header << "Confidence value" if confidence_available
      header << "Validation URI" if validation_uris
      header << "Compound URI"

      array = []
      array << header
      res.each do |a|
        array << header.collect{|h| a[h]}
      end

      if transformer.do_transform?
        array[0].each_with_index do |v,i|
          array[0][i] += "\n[#{transformer.unit}]" if ["Training value","Test value","Predicted value","Error"].include?(v)
        end
      end

      array
    end
  end

  ########## HACK FOR LOEAL MODELS ##############################
  
  class PredictionTransformer

    def initialize(compounds, prediction_feature_title)
      @prediction_feature_title = prediction_feature_title
      case prediction_feature_title
      when "LOAEL_log_mmol_kg_bw_day"
        @mw = {}
        OpenTox::Algorithm::Descriptor.physchem(compounds.collect{|c| OpenTox::Compound.new(c)},["Openbabel.mw"]).each do |uri,hash|
          @mw[uri] = hash["Openbabel.mw"].to_f
        end
      end
    end

    def do_transform?
      case @prediction_feature_title
      when /LOAEL_log_.mol_kg_bw_day/, "LOAEL_log_mg_kg_bw_day"
        true
      else
        false
      end
    end

    def unit
      case @prediction_feature_title
      when /LOAEL_log_.mol_kg_bw_day/
        "-log mol/kg bw/day"
      when "LOAEL_log_mg_kg_bw_day"
        "log mg/kg bw/day"
      else
        nil
      end
    end

    def transform_single(val, c_uri)
      case @prediction_feature_title
      when /LOAEL_log_.mol_kg_bw_day/
        val = (10**(-1*val)) * (@mw[c_uri]*1000)
      when "LOAEL_log_mg_kg_bw_day"
        val = 10**val
      else
        nil
      end
      val ? (val*10).round/10.0 : nil
    end

    def transform(val, c_uri)
      "["+[val].flatten.collect{|v| transform_single(v,c_uri)}.join(", ")+" mg/kg bw/day]"
    end
  end
end
