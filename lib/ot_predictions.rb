
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

    def compounds()
      @compounds
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
    
    def self.to_array( predictions, add_pic=false, format=false, validation_uris=nil )
 
      confidence_available = false
      predictions.each do |p|
        confidence_available |= p.confidence_values_available?
      end
      res = []
      conf_column = nil
      count = 0

      predictions.each do |p|
        v_uris = validation_uris[count] if validation_uris
        count += 1
        cmpds_mw = {}
        ds = OpenTox::Dataset.new()
        ds.save
       
        # Get MW of compounds
        p.compounds.each do |c_uri|
          ds.add_compound(c_uri)
          ds.save
        end 
        mw_algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"pc/MW")
        mw_uri = OpenTox::RestClientWrapper.post(mw_algorithm_uri, {:dataset_uri=>ds.uri})
        mw_ds = OpenTox::Dataset.find(mw_uri)
        p.compounds.each do |c_uri|
          cmpds_mw[c_uri] = mw_ds.data_entries[c_uri][mw_uri.to_s + "/feature/MW"].first
        end
        mw_ds.delete
        ds.delete 
        
        # Get prediction feature
        val = OpenTox::Validation.find(v_uris.first)
        p_feature = val.metadata[OT::predictionFeature].to_s.split("/").last

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

          if cmpds_mw[p.identifier(i)].nil? || (p.feature_type=="classification")
            a << (format ? p.actual_value(i).to_nice_s : p.actual_value(i))
            a << (format ? p.predicted_value(i).to_nice_s : p.predicted_value(i))
          else  # Converting values to mg values if found in prediction feature name
            if p.actual_value(i).nil?
              a << (format ? p.actual_value(i).to_nice_s : p.actual_value(i))
            else
              if p_feature.downcase.include? "ptd50"
                td50 = (((10**(-1.0*p.actual_value(i)))*(cmpds_mw[p.identifier(i)].to_f*1000))*1000).round / 1000.0
                a << (format ? "pTD50: " + p.actual_value(i).to_nice_s + "\n[TD50: " + td50.to_s.chomp + "]" : p.actual_value(i))
              elsif p_feature.downcase.include? "mol"
                mg = (((10**(-1.0*p.actual_value(i)))*(cmpds_mw[p.identifier(i)].to_f*1000))*1000).round / 1000.0
                a << (format ? "log mol/kg bw/day: " + p.actual_value(i).to_nice_s + "\n[mg/kg bw/day: " + mg.to_s.chomp + "]": p.actual_value(i))
              elsif p_feature.downcase.include? "mg"
                mg = ((10**p.actual_value(i))*1000).round / 1000.0
                a << (format ? "log mg/kg bw/day: " + p.actual_value(i).to_nice_s + "\n[mg/kg bw/day: " + mg.to_s.chomp + "]": p.actual_value(i))
              else
                a << (format ? p.actual_value(i).to_nice_s : p.actual_value(i))
              end
            end
            if p.predicted_value(i).nil?
              a << (format ? p.predicted_value(i).to_nice_s : p.predicted_value(i))
            else
              if p_feature.downcase.include? "ptd50"
                td50 = (((10**(-1.0*p.predicted_value(i)))*(cmpds_mw[p.identifier(i)].to_f*1000))*1000).round / 1000.0
                a << (format ? "pTD50: " + p.predicted_value(i).to_nice_s + "\n[TD50: " + td50.to_s.chomp + "]": p.predicted_value(i))
              elsif p_feature.downcase.include? "mol"
                mg = (((10**(-1.0*p.predicted_value(i)))*(cmpds_mw[p.identifier(i)].to_f*1000))*1000).round / 1000.0
                a << (format ? "log mol/kg bw/day: " + p.predicted_value(i).to_nice_s + "\n[mg/kg bw/day: " + mg.to_s.chomp + "]": p.predicted_value(i))
              elsif p_feature.downcase.include? "mg"
                mg = ((10**p.predicted_value(i))*1000).round / 1000.0
                a << (format ? "log mg/kg bw/day: " + p.predicted_value(i).to_nice_s + "\n[mg/kg bw/day: " + mg.to_s.chomp + "]": p.predicted_value(i))
              else
                a << (format ? p.predicted_value(i).to_nice_s : p.predicted_value(i))
              end
            end
          end
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
          if validation_uris
            a << v_uris[i]
          end
          a << p.identifier(i)
          # Get chemical names and add pubchem_iupac_name
          c = OpenTox::Compound.new(p.identifier(i))          
          c_names = c.to_names_hash          
          a << c_names["pubchem_iupac_name"]
          a << cmpds_mw[p.identifier(i)] 
         
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
      header << "Compound" if add_pic
      header << "Actual value"
      header << "Predicted value"
      header << "Classification" if predictions[0].feature_type=="classification"
      header << "Confidence value" if predictions[0].confidence_values_available?
      header << "Validation URI" if validation_uris
      header << "Compound URI"
      header << "Chemical name (pubchem_iupac_name)"
      header << "Molecular weight (openbabel)"
      res.insert(0, header)
      
      return res
    end
  end
end
