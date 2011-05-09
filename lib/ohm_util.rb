
module Lib
  module OhmUtil 
    
    def self.check_params(model, params)
      prop_names = model.attributes.collect{|p| p.to_s}
      params.keys.each do |k|
        key = k.to_s
        if (key == "subjectid")
          params.delete(k)
        else
          unless prop_names.include?(key)
            key = key.from_rdf_format
            unless prop_names.include?(key)
              key = key+"_uri"
              unless prop_names.include?(key)
                key = key+"s"
                unless prop_names.include?(key)
                  raise OpenTox::BadRequestError.new "no attribute found: '"+k.to_s+"'"
                end
              end
            end
          end
          params[key.to_sym] = params.delete(k)
        end
      end
      params
    end
    
    def self.find(model, filter_params)
      if (filter_params.size==0)
        model.all
      else
        model.find(check_params(model,filter_params))
      end
    end
    
  end 
end