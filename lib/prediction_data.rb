
module Lib
  
  class PredictionData
    
    CHECK_VALUES = ENV['RACK_ENV'] =~ /debug|test/
    
    def self.filter_data( data, compounds, min_confidence, min_num_predictions, max_num_predictions, prediction_index=nil )
      
      raise "cannot filter anything, no confidence values available" if data[:confidence_values][0]==nil
      raise OpenTox::BadRequestError.new "please specify either min_confidence or max_num_predictions" if 
        (min_confidence!=nil and max_num_predictions!=nil) || (min_confidence==nil and max_num_predictions==nil)
      raise OpenTox::BadRequestError.new "min_num_predictions only valid for min_confidence" if 
        (min_confidence==nil and min_num_predictions!=nil)
      min_num_predictions = 0 if min_num_predictions==nil
      
      LOGGER.debug("filtering predictions, conf:'"+min_confidence.to_s+"' min_num_predictions: '"+
        min_num_predictions.to_s+"' max_num_predictions: '"+max_num_predictions.to_s+"' ")
      #LOGGER.debug("to filter:\nconf: "+data[:confidence_values].inspect)
       
      orig_size = data[:predicted_values].size
      valid_indices = []
      data[:confidence_values].size.times do |i|
        next if prediction_index!=nil and prediction_index!=data[:predicted_values][i]
        valid = false
        if min_confidence!=nil
          valid = (valid_indices.size<=min_num_predictions or 
            (data[:confidence_values][i]!=nil and data[:confidence_values][i]>=min_confidence))
        else
          valid = valid_indices.size<max_num_predictions
        end
        valid_indices << i if valid
      end
      [ :predicted_values, :actual_values, :confidence_values ].each do |key|
        arr = []
        valid_indices.each{|i| arr << data[key][i]}
        data[key] = arr
      end
      if compounds!=nil
        new_compounds = []
        valid_indices.each{|i| new_compounds << compounds[i]}
      end
      LOGGER.debug("filtered predictions remaining: "+data[:predicted_values].size.to_s+"/"+orig_size.to_s)
      
      PredictionData.new(data, new_compounds)
    end
    
    def data
      @data
    end
    
    def compounds
      @compounds
    end
    
    def self.create( feature_type, test_dataset_uris, test_target_dataset_uris, 
      prediction_feature, prediction_dataset_uris, predicted_variables, predicted_confidences, 
      subjectid=nil, task=nil )      
      
      test_dataset_uris = [test_dataset_uris] unless test_dataset_uris.is_a?(Array)
      test_target_dataset_uris = [test_target_dataset_uris] unless test_target_dataset_uris.is_a?(Array)
      prediction_dataset_uris = [prediction_dataset_uris] unless prediction_dataset_uris.is_a?(Array)
      predicted_variables = [predicted_variables] unless predicted_variables.is_a?(Array)
      predicted_confidences = [predicted_confidences] unless predicted_confidences.is_a?(Array)
      LOGGER.debug "loading prediction -- test-dataset:       "+test_dataset_uris.inspect
      LOGGER.debug "loading prediction -- test-target-datset: "+test_target_dataset_uris.inspect
      LOGGER.debug "loading prediction -- prediction-dataset: "+prediction_dataset_uris.inspect
      LOGGER.debug "loading prediction -- predicted_variable: "+predicted_variables.inspect
      LOGGER.debug "loading prediction -- predicted_confidence: "+predicted_confidences.inspect
      LOGGER.debug "loading prediction -- prediction_feature: "+prediction_feature.to_s
      raise "prediction_feature missing" unless prediction_feature
      
      all_compounds = []
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
        tmp_compounds = []  
        compounds.each do |c|
          case feature_type
          when "classification"
            vals = classification_vals(test_target_dataset, c, prediction_feature, accept_values)
          when "regression"
            vals = regression_vals(test_target_dataset, c, prediction_feature)
          end
          vals.each do |v|
            actual_values << v
            tmp_compounds << c
          end
        end
        compounds = tmp_compounds
        task.progress( task_status += task_step ) if task # loaded actual values
      
        prediction_dataset = Lib::DatasetCache.find prediction_dataset_uri,subjectid
        raise "prediction dataset not found: '"+prediction_dataset_uri.to_s+"'" unless prediction_dataset
        
        # allow missing prediction feature if there are no compounds in the prediction dataset
        raise "predicted_variable not found in prediction_dataset\n"+
            "predicted_variable '"+predicted_variable.to_s+"'\n"+
            "prediction_dataset: '"+prediction_dataset_uri.to_s+"'\n"+
            "available features are: "+prediction_dataset.features.inspect if prediction_dataset.features.keys.index(predicted_variable)==nil and prediction_dataset.compounds.size>0
        raise "predicted_confidence not found in prediction_dataset\n"+
                "predicted_confidence '"+predicted_confidence.to_s+"'\n"+
                "prediction_dataset: '"+prediction_dataset_uri.to_s+"'\n"+
                "available features are: "+prediction_dataset.features.inspect if predicted_confidence and prediction_dataset.features.keys.index(predicted_confidence)==nil and prediction_dataset.compounds.size>0

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
        dup_compounds = []
        dup_actual_values = []
        count = 0
        compounds.size.times do |i|
          c = compounds[i]
          if prediction_dataset.compounds.index(c)==nil
            predicted_values << nil
            confidence_values << nil
            dup_compounds << c
            dup_actual_values << actual_values[i]
          else
            case feature_type
            when "classification"
              vals = classification_vals(prediction_dataset, c, predicted_variable, accept_values)
            when "regression"
              vals = regression_vals(prediction_dataset, c, predicted_variable)
            end
            
            #vals.uniq! #more than one prediciton is ok if it yields the equal value 
            #raise "not yet implemented: more than one prediction for one compound '#{vals.inspect}'" if vals.size>1
            #predicted_values << vals[0]
            
            if predicted_confidence
              conf_vals = confidence_vals(prediction_dataset, c, predicted_confidence) 
              conf_vals *= vals.size if conf_vals.size==1 and vals.size>1
              raise "confidence #{conf_vals.size} != predicted #{vals.size}" if conf_vals.size!=vals.size
            end
            
            idx = 0
            vals.each do |val|
              dup_compounds << c
              dup_actual_values << actual_values[i]
              predicted_values << val
              
              if predicted_confidence
                confidence_values << conf_vals[idx] 
              else
                confidence_values << nil
              end
              idx+=1
            end    
          end
          count += 1
        end
        all_compounds += dup_compounds
        all_predicted_values += predicted_values
        all_actual_values += dup_actual_values
        all_confidence_values += confidence_values
        
        task.progress( task_status += task_step ) if task # loaded predicted values and confidence
      end
      
      #sort according to confidence if available
      if all_confidence_values.compact.size>0
        values = []
        all_predicted_values.size.times do |i|
          values << [all_predicted_values[i], all_actual_values[i], all_confidence_values[i], all_compounds[i]]
        end
        values = values.sort_by{ |v| v[2] || 0 }.reverse # sorting by confidence
        all_predicted_values = []
        all_actual_values = []
        all_confidence_values = []
        all_compounds = []
        values.each do |v|
          all_predicted_values << v[0]
          all_actual_values << v[1]
          all_confidence_values << v[2]
          all_compounds << v[3]
        end
      end
      
      raise "illegal num compounds "+all_compounds.size.to_s+" != "+all_predicted_values.size.to_s if 
        all_compounds.size != all_predicted_values.size
      task.progress(100) if task # done with the mathmatics
      data = { :predicted_values => all_predicted_values, :actual_values => all_actual_values, :confidence_values => all_confidence_values,
        :feature_type => feature_type, :accept_values => accept_values }
        
      PredictionData.new(data, all_compounds)
    end
    
    private
    def initialize( data, compounds )
      @data = data
      @compounds = compounds
    end
    
    private
    def self.regression_vals(dataset, compound, feature)
      v_num = []
      values(dataset, compound, feature).each do |v|
        if v==nil or v.is_a?(Numeric)
          v_num << v
        else
          begin
            v_num << v.to_f
          rescue
            LOGGER.warn "no numeric value for regression: '"+v.to_s+"'"
            v_num << nil
          end
        end
      end
      v_num
    end
    
    def self.confidence_vals(dataset, compound, confidence)
      v_num = []
      values(dataset, compound, confidence).each do |v|
        if v==nil or v.is_a?(Numeric)
          v_num << v
        else
          begin
            v_num << v.to_f
          rescue
            LOGGER.warn "no numeric value for confidence: '"+v.to_s+"'"
            v_num << nil
          end
        end
      end
      v_num
    end
    
    def self.classification_vals(dataset, compound, feature, accept_values)
      v_indices = []
      values(dataset, compound, feature).each do |v|
        i = accept_values.index(v)
        raise "illegal class_value of prediction (value is '"+v.to_s+"'), accept values are "+
          accept_values.inspect unless v==nil or i!=nil
        v_indices << i
      end
      v_indices
    end
    
    def self.values(dataset, compound, feature)
      return [nil] if dataset.data_entries[compound]==nil
      if feature==nil
        v = dataset.data_entries[compound].values[0]
      else
        v = dataset.data_entries[compound][feature]
      end
      return [nil] if v==nil
      # sanitiy checks
      raise "no array "+v.class.to_s+" : '"+v.to_s+"'" unless v.is_a?(Array)
      v.each{|vv| raise "array-elem is array" if vv.is_a?(Array)} 
      # replace empty strings with nil
      v_mod = v.collect{|vv| (vv.to_s().size==0 ? nil : vv)}
      v_mod
    end    
  end
end
