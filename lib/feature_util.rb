
module Lib
  class FeatureUtil
    
    # this derieves the predicted_variable and predicted_confidence in prediction dataset
    # predicted_variable: the feature-uri of model predictions
    # predicted_confidence: the feature-uri of the model prediction confidence
    # according to API info should be available in the API
    # problem: IST has no feature-service -> predicted_variable depends on prediction dataset 
    #
    # PENDING: ambit and ist declare prediction features differently -> unify
    #
    def self.predicted_variables( model, prediction_dataset_uri, subjectid=nil )
      
      predicted_variable = nil
      predicted_confidence = nil
      
      if model.metadata[OT.predictedVariables]
        predictedVariables = model.metadata[OT.predictedVariables]
        if predictedVariables.is_a?(Array)
          if (predictedVariables.size==1)
            predicted_variable = predictedVariables[0]
          elsif (predictedVariables.size==2)
            # PENDING identify confidence
            conf_index = -1
            predictedVariables.size.times do |i|
              conf_index = i if OpenTox::Feature.find(predictedVariables[i]).metadata[DC.title]=~/(?i)confidence/
            end
            raise "size=2, no confidence "+predictedVariables.inspect+" "+model.uri.to_s if conf_index==-1
            predicted_variable = predictedVariables[1-conf_index]
            predicted_confidence = predictedVariables[conf_index]
          else
            raise "size>2 "+predictedVariables.inspect+" "+model.uri.to_s  
          end
        else
          raise "predictedVariables is no array"
        end        
      end
      
      unless predicted_variable
        d = OpenTox::Dataset.new prediction_dataset_uri
        d.load_features(subjectid)
        d.features.keys.each do |f|
          if d.features[f][OT.hasSource]==model.uri
            puts "source matching"
            # PENDING identify confidence
            if f =~ /(?i)confidence/
              puts "conf matiching"
              raise "duplicate confidence feature, what to choose?" if predicted_confidence!=nil
              predicted_confidence = f
            elsif d.features[f][RDF.type].include? OT.ModelPrediction
              puts "type include prediction"
              raise "duplicate predicted variable, what to choose?" if predicted_variable!=nil
              predicted_variable = f
            end
          end
          puts d.features[f][OT.hasSource]
        end
        raise "could not estimate predicted variable" unless predicted_variable
      end
      
      {:predicted_variable => predicted_variable, :predicted_confidence => predicted_confidence}
    end
  end
end
  
