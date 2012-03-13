
require "lib/prediction_data.rb"
require "lib/predictions.rb"

module Lib
  
  class OTPredictions < Predictions
  
    def initialize(data, compounds=nil)
      raise unless data.is_a?(Hash)
      super(data)
      @compounds = compounds
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
