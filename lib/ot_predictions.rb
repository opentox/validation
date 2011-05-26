
require "lib/predictions.rb"

module Lib
  
  class OTPredictions < Predictions
  
    CHECK_VALUES = ENV['RACK_ENV'] =~ /debug|test/
  
    def identifier(instance_index)
      return compound(instance_index)
    end
  
    def compound(instance_index)
      return @compounds[instance_index]
    end
  
    def initialize( feature_type, test_dataset_uris, test_target_dataset_uris, 
      prediction_feature, prediction_dataset_uris, predicted_variables, predicted_confidences, subjectid=nil, task=nil)      
      
        test_dataset_uris = [test_dataset_uris] unless test_dataset_uris.is_a?(Array)
        test_target_dataset_uris = [test_target_dataset_uris] unless test_target_dataset_uris.is_a?(Array)
        prediction_dataset_uris = [prediction_dataset_uris] unless prediction_dataset_uris.is_a?(Array)
        predicted_variables = [predicted_variables] unless predicted_variables.is_a?(Array)
        predicted_confidences = [predicted_confidences] unless predicted_confidences.is_a?(Array)
        LOGGER.debug "loading prediciton -- test-dataset:       "+test_dataset_uris.inspect
        LOGGER.debug "loading prediciton -- test-target-datset: "+test_target_dataset_uris.inspect
        LOGGER.debug "loading prediciton -- prediction-dataset: "+prediction_dataset_uris.inspect
        LOGGER.debug "loading prediciton -- predicted_variable: "+predicted_variables.inspect
        LOGGER.debug "loading prediciton -- predicted_confidence: "+predicted_confidences.inspect
        LOGGER.debug "loading prediciton -- prediction_feature: "+prediction_feature.to_s
        raise "prediction_feature missing" unless prediction_feature
        
        @compounds = []
        all_predicted_values = []
        all_actual_values = []
        all_confidence_values = []
        accept_values = nil
        
        if task
          task_step = 100 / (test_dataset_uris.size*2 + 1)
          task_status = 0
        end

        test_dataset_uris.size.times do |i|
          
          test_dataset_uri = test_dataset_uris[i]
          test_target_dataset_uri = test_target_dataset_uris[i]
          prediction_dataset_uri = prediction_dataset_uris[i]
          predicted_variable = predicted_variables[i]
          predicted_confidence = predicted_confidences[i]
          
          predicted_variable=prediction_feature if predicted_variable==nil
        
          test_dataset = Lib::DatasetCache.find test_dataset_uri,subjectid
          raise "test dataset not found: '"+test_dataset_uri.to_s+"'" unless test_dataset
        
          if test_target_dataset_uri == nil || test_target_dataset_uri.strip.size==0 || test_target_dataset_uri==test_dataset_uri
            test_target_dataset_uri = test_dataset_uri
            test_target_dataset = test_dataset
            raise "prediction_feature not found in test_dataset, specify a test_target_dataset\n"+
                  "prediction_feature: '"+prediction_feature.to_s+"'\n"+
                  "test_dataset: '"+test_target_dataset_uri.to_s+"'\n"+
                  "available features are: "+test_target_dataset.features.inspect if test_target_dataset.features.keys.index(prediction_feature)==nil
          else
            test_target_dataset = Lib::DatasetCache.find test_target_dataset_uri,subjectid
            raise "test target datset not found: '"+test_target_dataset_uri.to_s+"'" unless test_target_dataset
            if CHECK_VALUES
              test_dataset.compounds.each do |c|
                raise "test compound not found on test class dataset "+c.to_s unless test_target_dataset.compounds.include?(c)
              end
            end
            raise "prediction_feature not found in test_target_dataset\n"+
                  "prediction_feature: '"+prediction_feature.to_s+"'\n"+
                  "test_target_dataset: '"+test_target_dataset_uri.to_s+"'\n"+
                  "available features are: "+test_target_dataset.features.inspect if test_target_dataset.features.keys.index(prediction_feature)==nil
          end
          
          compounds = test_dataset.compounds
          LOGGER.debug "test dataset size: "+compounds.size.to_s
          raise "test dataset is empty "+test_dataset_uri.to_s unless compounds.size>0
          
          if feature_type=="classification"
            av = test_target_dataset.accept_values(prediction_feature)
            raise "'"+OT.acceptValue.to_s+"' missing/invalid for feature '"+prediction_feature.to_s+"' in dataset '"+
              test_target_dataset_uri.to_s+"', acceptValues are: '"+av.inspect+"'" if av==nil or av.length<2
            if accept_values==nil
              accept_values=av
            else
              raise "accept values (in folds) differ "+av.inspect+" != "+accept_values.inspect if av!=accept_values
            end
          end
          
          actual_values = []
          compounds.each do |c|
            case feature_type
            when "classification"
              actual_values << classification_val(test_target_dataset, c, prediction_feature, accept_values)
            when "regression"
              actual_values << regression_val(test_target_dataset, c, prediction_feature)
            end
          end
          task.progress( task_status += task_step ) if task # loaded actual values
        
          prediction_dataset = Lib::DatasetCache.find prediction_dataset_uri,subjectid
          raise "prediction dataset not found: '"+prediction_dataset_uri.to_s+"'" unless prediction_dataset
          raise "predicted_variable not found in prediction_dataset\n"+
                  "predicted_variable '"+predicted_variable.to_s+"'\n"+
                  "prediction_dataset: '"+prediction_dataset_uri.to_s+"'\n"+
                  "available features are: "+prediction_dataset.features.inspect if prediction_dataset.features.keys.index(predicted_variable)==nil
          raise "predicted_confidence not found in prediction_dataset\n"+
                  "predicted_confidence '"+predicted_confidence.to_s+"'\n"+
                  "prediction_dataset: '"+prediction_dataset_uri.to_s+"'\n"+
                  "available features are: "+prediction_dataset.features.inspect if predicted_confidence and prediction_dataset.features.keys.index(predicted_confidence)==nil

          raise "more predicted than test compounds, #test: "+compounds.size.to_s+" < #prediction: "+
            prediction_dataset.compounds.size.to_s+", test-dataset: "+test_dataset_uri.to_s+", prediction-dataset: "+
             prediction_dataset_uri if compounds.size < prediction_dataset.compounds.size
          if CHECK_VALUES
            prediction_dataset.compounds.each do |c| 
              raise "predicted compound not found in test dataset:\n"+c+"\ntest-compounds:\n"+
                compounds.collect{|c| c.to_s}.join("\n") if compounds.index(c)==nil
            end
          end
          
          predicted_values = []
          confidence_values = []
          count = 0
          compounds.each do |c|
            if prediction_dataset.compounds.index(c)==nil
              predicted_values << nil
              confidence_values << nil
            else
              case feature_type
              when "classification"
                predicted_values << classification_val(prediction_dataset, c, predicted_variable, accept_values)
              when "regression"
                predicted_values << regression_val(prediction_dataset, c, predicted_variable)
              end
              if predicted_confidence
                confidence_values << confidence_val(prediction_dataset, c, predicted_confidence)
              else
                confidence_values << nil
              end
            end
            count += 1
          end
          @compounds += compounds
          all_predicted_values += predicted_values
          all_actual_values += actual_values
          all_confidence_values += confidence_values
          
          task.progress( task_status += task_step ) if task # loaded predicted values and confidence
        end
        
      super(all_predicted_values, all_actual_values, all_confidence_values, feature_type, accept_values)
      raise "illegal num compounds "+num_info if  @compounds.size != @predicted_values.size
      task.progress(100) if task # done with the mathmatics
    end
    
    private
    def regression_val(dataset, compound, feature)
      v = value(dataset, compound, feature)
      begin
        v = v.to_f unless v==nil or v.is_a?(Numeric)
        v
      rescue
        LOGGER.warn "no numeric value for regression: '"+v.to_s+"'"
        nil
      end
    end
    
    def confidence_val(dataset, compound, confidence)
      v = value(dataset, compound, confidence)
      begin
        v = v.to_f unless v==nil or v.is_a?(Numeric)
        v
      rescue
        LOGGER.warn "no numeric value for confidence '"+v.to_s+"'"
        nil
      end
    end
    
    def classification_val(dataset, compound, feature, accept_values)
      v = value(dataset, compound, feature)
      i = accept_values.index(v.to_s)
      raise "illegal class_value of prediction (value is '"+v.to_s+"'), accept values are "+
        accept_values.inspect unless v==nil or i!=nil
      i
    end
    
    def value(dataset, compound, feature)
      return nil if dataset.data_entries[compound]==nil
      if feature==nil
        v = dataset.data_entries[compound].values[0]
      else
        v = dataset.data_entries[compound][feature]
      end
      return nil if v==nil 
      raise "no array "+v.class.to_s+" : '"+v.to_s+"'" unless v.is_a?(Array)
      if v.size>1
        v.uniq!
        if v.size>1
          v = nil
          LOGGER.warn "not yet implemented: multiple non-equal values "+compound.to_s+" "+v.inspect
        else
          v = v[0]
        end
      elsif v.size==1
        v = v[0]
      else
        v = nil
      end
      raise "array" if v.is_a?(Array)
      v = nil if v.to_s.size==0
      v
    end

    public
    def compute_stats
    
      res = {}
      case @feature_type
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
    
    def self.to_array( predictions, add_pic=false, format=false )
  
      confidence_available = false
      predictions.each do |p|
        confidence_available |= p.confidence_values_available?
      end
      res = []
      conf_column = nil
      predictions.each do |p|
        (0..p.num_instances-1).each do |i|
          a = []
          
          #PENDING!
          begin
            #a.push( "http://ambit.uni-plovdiv.bg:8080/ambit2/depict/cdk?search="+
            #  URI.encode(OpenTox::Compound.new(:uri=>p.identifier(i)).smiles) ) if add_pic
            a << p.identifier(i)+"?media=image/png"
          rescue => ex
            raise ex
            #a.push("Could not add pic: "+ex.message)
            #a.push(p.identifier(i))
          end
          
          a << (format ? p.actual_value(i).to_nice_s : p.actual_value(i))
          a << (format ? p.predicted_value(i).to_nice_s : p.predicted_value(i))
          if p.feature_type=="classification"
            if (p.predicted_value(i)!=nil and p.actual_value(i)!=nil)
              if p.classification_miss?(i)
                a << (format ? ICON_ERROR : 1)
              else
                a << (format ? ICON_OK : 0)
              end
            else
              a << nil
            end
          end
          if confidence_available
            conf_column = a.size if conf_column==nil
            a << p.confidence_value(i)
          end
          a << p.identifier(i)
          res << a
        end
      end
      
      if conf_column!=nil
        LOGGER.debug "sort via confidence: "+res.collect{|n| n[conf_column]}.inspect
        res = res.sort_by{ |n| n[conf_column] || 0 }.reverse
        if format
          res.each do |a|
            a[conf_column] = a[conf_column].to_nice_s
          end
        end
      end
      header = []
      header << "compound" if add_pic
      header << "actual value"
      header << "predicted value"
      header << "classification" if predictions[0].feature_type=="classification"
      header << "confidence value" if predictions[0].confidence_values_available?
      header << "compound-uri"
      res.insert(0, header)
      
      return res
    end
  end
end
