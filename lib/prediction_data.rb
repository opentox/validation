
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
    
    def self.create( feature_type, test_dataset_uris, prediction_feature, prediction_dataset_uris, 
      predicted_variables, predicted_confidences, subjectid=nil, task=nil )      
      
      test_dataset_uris = [test_dataset_uris] unless test_dataset_uris.is_a?(Array)
      prediction_dataset_uris = [prediction_dataset_uris] unless prediction_dataset_uris.is_a?(Array)
      predicted_variables = [predicted_variables] unless predicted_variables.is_a?(Array)
      predicted_confidences = [predicted_confidences] unless predicted_confidences.is_a?(Array)
      LOGGER.debug "loading prediction -- test-dataset:       "+test_dataset_uris.inspect
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
        prediction_dataset_uri = prediction_dataset_uris[i]
        predicted_variable = predicted_variables[i]
        predicted_confidence = predicted_confidences[i]
        
        predicted_variable=prediction_feature if predicted_variable==nil
      
        test_dataset = Lib::DatasetCache.find test_dataset_uri,subjectid
        raise "test dataset not found: '"+test_dataset_uri.to_s+"'" unless test_dataset
      
        raise "prediction_feature not found in test_dataset\n"+
              "prediction_feature: '"+prediction_feature.to_s+"'\n"+
              "test_dataset: '"+test_dataset_uri.to_s+"'\n"+
              "available features are: "+test_dataset.features.inspect if test_dataset.features.keys.index(prediction_feature)==nil
        
        LOGGER.debug "test dataset size: "+test_dataset.compounds.size.to_s
        raise "test dataset is empty "+test_dataset_uri.to_s unless test_dataset.compounds.size>0
        
        if feature_type=="classification"
          av = test_dataset.accept_values(prediction_feature)
          raise "'"+OT.acceptValue.to_s+"' missing/invalid for feature '"+prediction_feature.to_s+"' in dataset '"+
            test_dataset_uri.to_s+"', acceptValues are: '"+av.inspect+"'" if av==nil or av.length<2
          if accept_values==nil
            accept_values=av
          else
            raise "accept values (in folds) differ "+av.inspect+" != "+accept_values.inspect if av!=accept_values
          end
        end
        
        actual_values = []
        test_dataset.compounds.size.times do |c_idx|
          case feature_type
          when "classification"
            actual_values << classification_val(test_dataset, c_idx, prediction_feature, accept_values)
          when "regression"
            actual_values << numeric_val(test_dataset, c_idx, prediction_feature)
          end
          #raise "WTF #{c_idx} #{test_dataset.compounds[c_idx]} #{actual_values[-1]} #{actual_values[-2]}" if c_idx>0 and test_dataset.compounds[c_idx]==test_dataset.compounds[c_idx-1] and actual_values[-1]!=actual_values[-2]
        end
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

        raise "more predicted than test compounds, #test: "+test_dataset.compounds.size.to_s+" < #prediction: "+
          prediction_dataset.compounds.size.to_s+", test-dataset: "+test_dataset_uri.to_s+", prediction-dataset: "+
           prediction_dataset_uri if test_dataset.compounds.size < prediction_dataset.compounds.size
        if CHECK_VALUES
          prediction_dataset.compounds.each do |c| 
            raise "predicted compound not found in test dataset:\n"+c+"\ntest-compounds:\n"+
              test_dataset.compounds.collect{|c| c.to_s}.join("\n") unless test_dataset.compounds.include?(c)
          end
        end
        
        predicted_values = []
        confidence_values = []
        
        test_dataset.compounds.size.times do |test_c_idx|
          c = test_dataset.compounds[test_c_idx]
          pred_c_idx = prediction_dataset.compound_index(test_dataset,test_c_idx)
          if pred_c_idx==nil
            raise "internal error: mapping failed" if prediction_dataset.compounds.include?(c)
            predicted_values << nil
            confidence_values << nil
          else
            raise "internal error: mapping failed" unless c==prediction_dataset.compounds[pred_c_idx]  
            case feature_type
            when "classification"
              predicted_values << classification_val(prediction_dataset, pred_c_idx, predicted_variable, accept_values)
            when "regression"
              predicted_values << numeric_val(prediction_dataset, pred_c_idx, predicted_variable)
            end
            if predicted_confidence
              confidence_values << numeric_val(prediction_dataset, pred_c_idx, predicted_confidence)
            else
              confidence_values << nil
            end
          end
        end
        all_compounds += test_dataset.compounds
        all_predicted_values += predicted_values
        all_actual_values += actual_values
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
    def self.numeric_val(dataset, compound_index, feature)
      v = dataset.data_entry_value(compound_index, feature)
      begin
        v = v.to_f unless v==nil or v.is_a?(Numeric)
        v
      rescue
        LOGGER.warn "no numeric value for feature '#{feature}' : '#{v}'"
        nil
      end
    end
    
    def self.classification_val(dataset, compound_index, feature, accept_values)
      v = dataset.data_entry_value(compound_index, feature)
      i = accept_values.index(v)
      raise "illegal class_value of prediction (value is '"+v.to_s+"'), accept values are "+
        accept_values.inspect unless v==nil or i!=nil
      i
    end
  end
end
