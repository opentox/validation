# pending: package dir hack ---------
# CONFIG[:base_dir] = "/home/<user>/opentox-ruby/www"
# PACKAGE_DIR = "/home/<user>/opentox-ruby/r-packages"
package_dir = CONFIG[:base_dir].split("/")
package_dir[-1] = "r-packages"
package_dir = package_dir.join("/")
PACKAGE_DIR = package_dir



module Lib
  
  module RUtil
    
    def self.dataset_to_dataframe( dataset )
      LOGGER.debug "convert dataset to dataframe #{dataset.uri}"
      all_features = []
      dataset.features.each do |f|
        feat_name = "feature_#{f[0].split("/")[-1]}"
        LOGGER.debug "- adding feature: #{feat_name}"
        feat = OpenTox::Feature.find(f[0])
        nominal = feat.metadata[RDF.type].to_a.flatten.include?(OT.NominalFeature)
        values = []
        dataset.compounds.each do |c|
          val = dataset.data_entries[c][f[0]]
          raise "not yet implemented" if val!=nil && val.size>1
          v = val==nil ? "" : val[0].to_s
          v = "NA" if v.size()==0
          values << v
        end
        all_features << feat_name
        @@r.assign feat_name,values
        @@r.eval "#{feat_name} <- as.numeric(#{feat_name})" unless nominal
      end
      df_name = "df_#{dataset.uri.split("/")[-1].split("?")[0]}"
      cmd =  "#{df_name} <- data.frame(#{all_features.join(",")})"
      @@r.eval cmd
      #@@r.eval "head(#{df_name})"
      df_name
    end
    
    def self.stratified_split( dataframe, pct=0.3, seed=42 )
      @@r.eval "set.seed(#{seed})"
      @@r.eval "split <- stratified_split(#{dataframe}, ratio=#{pct})"
      split = @@r.pull 'split'
      split.collect{|s| s.to_i}
    end
    
    def self.package_installed?( package )
      @@r.eval ".libPaths(\"#{PACKAGE_DIR}\")"
      p = @@r.pull "installed.packages()[,1]"
      p.include?(package) 
    end
    
    def self.install_packages( package )
      unless package_installed? package
        @@r.eval "install.packages(\"#{package}\", repos=\"http://cran.r-project.org\", dependencies=T, lib=\"#{PACKAGE_DIR}\")"
      end
    end
    
    def self.library( package )
      install_packages( package )
      @@r.eval "library(\"#{package}\")"
    end
    
    def self.init_r
      @@r = RinRuby.new(true,false) unless defined?(@@r) and @@r
      library("sampling")
      library("gam")
      @@r.eval "source(\"#{PACKAGE_DIR}/stratification.R\")"
    end
    
    def self.quit_r
      begin
        @@r.quit
        @@r = nil
      rescue
      end
    end
    
  end
end
