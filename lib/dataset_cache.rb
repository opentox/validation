
module Lib
  
  module DatasetCache
    
    @@cache={}

    # same as OpenTox::Dataset.find with caching function
    # rational: datasets are reused in crossvalidation very often, cache to save computational effort
    # PENDING: may cause memory issues, test with huge datasets 
    def self.find(dataset_uri)
      return nil if (dataset_uri==nil)
      d = @@cache[dataset_uri.to_s+"_"+OpenTox::RestClientWrapper.subjectid.to_s]
      if d==nil
        d = OpenTox::Dataset.find(dataset_uri)
        @@cache[dataset_uri.to_s+"_"+OpenTox::RestClientWrapper.subjectid.to_s] = d
      end
      d
    end
    
  end
  
end
