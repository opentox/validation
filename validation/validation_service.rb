

require "lib/validation_db.rb"
require "lib/ot_predictions.rb"

require "validation/validation_format.rb"


class Array
  
  # cuts an array into <num-pieces> chunks
  def chunk(pieces)
    q, r = length.divmod(pieces)
    (0..pieces).map { |i| i * q + [r, i].min }.enum_cons(2) \
    .map { |a, b| slice(a...b) }
  end

  # shuffles the elements of an array
  def shuffle( seed=nil )
    srand seed.to_i if seed
    sort_by { Kernel.rand }
  end

  # shuffels self
  def shuffle!( seed=nil )
    self.replace shuffle( seed )
  end

end

module Validation
  
  class Validation
    
    def self.from_cv_statistics( cv_id, subjectid=nil, waiting_task=nil )
      v =  Validation.find( :crossvalidation_id => cv_id, :validation_type => "crossvalidation_statistics" ).first
      unless v
        crossvalidation = Crossvalidation.get(cv_id)
        raise OpenTox::NotFoundError.new "Crossvalidation '#{cv_id}' not found." unless crossvalidation
        raise OpenTox::BadRequestError.new "Crossvalidation '"+cv_id.to_s+"' not finished" unless crossvalidation.finished
        vals = Validation.find( :crossvalidation_id => cv_id, :validation_type => "crossvalidation" ).collect{|x| x}
        
        v = Validation.new
        v.subjectid = subjectid
        v.compute_prediction_data_with_cv(vals, waiting_task)
        v.compute_validation_stats()
          
        (VAL_PROPS_GENERAL-[:validation_uri]).each do |p|
          v.send("#{p.to_s}=".to_sym, vals.collect{ |vv| vv.send(p) }.uniq.join(";"))
        end
        v.date = crossvalidation.date
        v.validation_type = "crossvalidation_statistics"
        v.crossvalidation_id = crossvalidation.id
        v.crossvalidation_fold = vals.collect{ |vv| vv.crossvalidation_fold }.uniq.join(";")       
        v.real_runtime = vals.collect{ |vv| vv.real_runtime }.uniq.join(";")
        v.save
      end
      v.subjectid = subjectid
      waiting_task.progress(100) if waiting_task
      v
    end
    
    # deletes a validation
    # PENDING: model and referenced datasets are deleted as well, keep it that way?
    def delete_validation( delete_all=true )
      if (delete_all)
        to_delete = [:model_uri, :training_dataset_uri, :test_dataset_uri, :test_target_dataset_uri, :prediction_dataset_uri ]
        case self.validation_type
        when "test_set_validation"
          to_delete -= [ :model_uri, :training_dataset_uri, :test_dataset_uri, :test_target_dataset_uri ]
        when "bootstrapping"
          to_delete -= [ :test_target_dataset_uri ]
        when "training_test_validation"
          to_delete -=  [ :training_dataset_uri, :test_dataset_uri, :test_target_dataset_uri ]
        when "training_test_split"
          to_delete -= [ :test_target_dataset_uri ]
        when "validate_datasets"
          to_delete = []
        when "crossvalidation"
          to_delete -= [ :test_target_dataset_uri ]
        when "crossvalidation_statistics"
          to_delete = []
        else
          raise "unknown validation type '"+self.validation_type.to_s+"'"
        end
        Thread.new do # do deleting in background to not cause a timeout
          to_delete.each do |attr|
            uri = self.send(attr)
            LOGGER.debug "also deleting "+attr.to_s+" : "+uri.to_s if uri
            begin
              OpenTox::RestClientWrapper.delete(uri, :subjectid => subjectid) if uri
              sleep 1 if AA_SERVER # wait a second to not stress the a&a service too much
            rescue => ex
              LOGGER.warn "could not delete "+uri.to_s+" : "+ex.message.to_s
            end
          end
        end
      end
      self.delete
      if (subjectid)
        Thread.new do
          begin
            res = OpenTox::Authorization.delete_policies_from_uri(validation_uri, subjectid)
            LOGGER.debug "Deleted validation policy: #{res}"
          rescue
            LOGGER.warn "Policy delete error for validation: #{validation_uri}"
          end
        end
      end
      "Successfully deleted validation "+self.id.to_s+"."
    end
    
    # validates an algorithm by building a model and validating this model
    def validate_algorithm( task=nil )
      raise "validation_type missing" unless self.validation_type
      raise OpenTox::BadRequestError.new "no algorithm uri: '"+self.algorithm_uri.to_s+"'" if self.algorithm_uri==nil or self.algorithm_uri.to_s.size<1
      
      params = { :dataset_uri => self.training_dataset_uri, :prediction_feature => self.prediction_feature }
      if (self.algorithm_params!=nil)
        self.algorithm_params.split(";").each do |alg_params|
          alg_param = alg_params.split("=",2)
          raise OpenTox::BadRequestError.new "invalid algorithm param: '"+alg_params.to_s+"'" unless alg_param.size==2 or alg_param[0].to_s.size<1 or alg_param[1].to_s.size<1
          LOGGER.warn "algorihtm param contains empty space, encode? "+alg_param[1].to_s if alg_param[1] =~ /\s/
          params[alg_param[0].to_sym] = alg_param[1]
        end
      end
      
      algorithm = OpenTox::Algorithm::Generic.new(algorithm_uri)
      params[:subjectid] = subjectid
      self.model_uri = algorithm.run(params, OpenTox::SubTask.create(task, 0, 33))
      
      #model = OpenTox::Model::PredictionModel.build(algorithm_uri, params, 
      #  OpenTox::SubTask.create(task, 0, 33) )
      
      raise "model building failed" unless model_uri
      #self.attributes = { :model_uri => model_uri }
      #self.save!
      
#      self.save if self.new?
#      self.update :model_uri => model_uri
      
      #raise "error after building model: model.dependent_variable != validation.prediciton_feature ("+
      #  model.dependentVariables.to_s+" != "+self.prediction_feature+")" if self.prediction_feature!=model.dependentVariables
          
      validate_model OpenTox::SubTask.create(task, 33, 100)
    end
    
    # validates a model
    # PENDING: a new dataset is created to store the predictions, this should be optional: delete predictions afterwards yes/no
    def validate_model( task=nil )
      
      raise "validation_type missing" unless self.validation_type
      LOGGER.debug "validating model '"+self.model_uri+"'"
      
      #model = OpenTox::Model::PredictionModel.find(self.model_uri)
      #raise OpenTox::NotFoundError.new "model not found: "+self.model_uri.to_s unless model
      model = OpenTox::Model::Generic.find(self.model_uri, self.subjectid)
      
      unless self.algorithm_uri
        self.algorithm_uri = model.metadata[OT.algorithm]
      end
      if self.prediction_feature.to_s.size==0
        dependentVariables = model.metadata[OT.dependentVariables]
        raise OpenTox::NotFoundError.new "model has no dependentVariables specified, please give prediction_feature for model validation" unless dependentVariables
        self.prediction_feature = model.metadata[OT.dependentVariables]
      end
      
      prediction_dataset_uri = ""
      benchmark = Benchmark.measure do 
        #prediction_dataset_uri = model.predict_dataset(self.test_dataset_uri, OpenTox::SubTask.create(task, 0, 50))
        prediction_dataset_uri = model.run(
          {:dataset_uri => self.test_dataset_uri, :subjectid => self.subjectid},
          "text/uri-list",
          OpenTox::SubTask.create(task, 0, 50))
      end
#      self.attributes = { :prediction_dataset_uri => prediction_dataset_uri,
#             :real_runtime => benchmark.real }
#      self.save!
#      self.update :prediction_dataset_uri => prediction_dataset_uri,
#                  :real_runtime => benchmark.real
      self.prediction_dataset_uri = prediction_dataset_uri
      self.real_runtime = benchmark.real
             
      compute_prediction_data_with_model( model, OpenTox::SubTask.create(task, 50, 100) )
      compute_validation_stats()
    end
    
    def compute_prediction_data_with_cv(cv_vals, waiting_task=nil)
      models = cv_vals.collect{|v| OpenTox::Model::Generic.find(v.model_uri, subjectid)}
      feature_type = models.first.feature_type(subjectid)
      test_dataset_uris = cv_vals.collect{|v| v.test_dataset_uri}
      test_target_dataset_uris = cv_vals.collect{|v| v.test_target_dataset_uri}
      prediction_feature = cv_vals.first.prediction_feature
      prediction_dataset_uris = cv_vals.collect{|v| v.prediction_dataset_uri}
      predicted_variables = models.collect{|m| m.predicted_variable(subjectid)}
      predicted_confidences = models.collect{|m| m.predicted_confidence(subjectid)}
      p_data = Lib::PredictionData.create( feature_type, test_dataset_uris, test_target_dataset_uris, prediction_feature, 
        prediction_dataset_uris, predicted_variables, predicted_confidences, subjectid, waiting_task )
      self.prediction_data = p_data.data
      p_data.data
    end
    
    def compute_prediction_data_with_model(model=nil, task=nil)
      model = OpenTox::Model::Generic.find(self.model_uri, self.subjectid) if model==nil and self.model_uri
      raise OpenTox::NotFoundError.new "model not found: "+self.model_uri.to_s unless model
      
      feature_type = model.feature_type(self.subjectid)
      dependentVariables = model.metadata[OT.dependentVariables]
      prediction_feature = self.prediction_feature ? nil : dependentVariables
      algorithm_uri = self.algorithm_uri ? nil : model.metadata[OT.algorithm]
      predicted_variable = model.predicted_variable(self.subjectid)
      predicted_confidence = model.predicted_confidence(self.subjectid)
      raise "cannot determine whether model '"+model.uri.to_s+"' performs classification or regression: '#{feature_type}', "+
          "please set rdf-type of predictedVariables feature '"+predicted_variable.to_s+
          "' to NominalFeature or NumericFeature" if
          (feature_type.to_s!="classification" and feature_type.to_s!="regression")        
      compute_prediction_data( feature_type, predicted_variable, predicted_confidence, 
        prediction_feature, algorithm_uri, task )
    end
    
    def compute_prediction_data( feature_type, predicted_variable, predicted_confidence, prediction_feature, 
        algorithm_uri, task )
      self.prediction_feature = prediction_feature if self.prediction_feature==nil && prediction_feature
      self.algorithm_uri = algorithm_uri if self.algorithm_uri==nil && algorithm_uri
    
      LOGGER.debug "computing prediction stats"
      p_data = Lib::PredictionData.create( feature_type, 
        self.test_dataset_uri, self.test_target_dataset_uri, self.prediction_feature, 
        self.prediction_dataset_uri, predicted_variable, predicted_confidence, self.subjectid,
        OpenTox::SubTask.create(task, 0, 80) )
      self.prediction_data = p_data.data
      task.progress(100) if task
      p_data.data
    end
    
    def compute_validation_stats( save_stats=true )
      p_data = self.prediction_data
      raise "compute prediction data before" if p_data==nil
      predictions = Lib::OTPredictions.new(p_data)
      case p_data[:feature_type]
      when "classification"
        self.classification_statistics = predictions.compute_stats()
      when "regression"
        self.regression_statistics = predictions.compute_stats()
      end
      self.num_instances = predictions.num_instances
      self.num_without_class = predictions.num_without_class
      self.percent_without_class = predictions.percent_without_class
      self.num_unpredicted = predictions.num_unpredicted
      self.percent_unpredicted = predictions.percent_unpredicted
      if (save_stats)
        self.finished = true
        self.save
        raise unless self.valid?
      end
    end
    
    def filter_predictions( min_confidence, min_num_predictions, max_num_predictions, prediction=nil )
      self.prediction_data = nil
      self.save
      
      raise OpenTox::BadRequestError.new "only supported for classification" if prediction!=nil and classification_statistics==nil
      raise OpenTox::BadRequestError.new "illegal confidence value #{min_confidence}" unless 
        min_confidence==nil or (min_confidence.is_a?(Numeric) and min_confidence>=0 and min_confidence<=1)
      p_data = self.prediction_data
      if p_data==nil
        # this is to ensure backwards compatibilty
        # may cause a timeout on the first run, as this is not meant to run in a task
        if validation_type=="crossvalidation_statistics"
          vals = Validation.find( :crossvalidation_id => self.crossvalidation_id, :validation_type => "crossvalidation" ).collect{|x| x}
          compute_prediction_data_with_cv(vals)
        else
          compute_prediction_data_with_model
        end
        self.save
        p_data = self.prediction_data
      end
      raise OpenTox::BadRequestError.new("illegal prediction value: '"+prediction+"', available: "+
        p_data[:accept_values].inspect) if prediction!=nil and p_data[:accept_values].index(prediction)==nil
      p = Lib::PredictionData.filter_data(p_data, nil, min_confidence, min_num_predictions, max_num_predictions,
        prediction==nil ? nil : p_data[:accept_values].index(prediction))
      self.prediction_data = p.data
      compute_validation_stats(false)
    end
    
    def probabilities( confidence, prediction )
      filter_predictions( confidence, 12, nil, prediction )
      p_data = self.prediction_data
      p = Lib::Predictions.new(p_data)
      prediction_counts = p.confusion_matrix_row( p_data[:accept_values].index(prediction) )
      sum = 0
      prediction_counts.each{|v| sum+=v}
      probs = {}
      p_data[:accept_values].size.times do |i|
          probs[p_data[:accept_values][i]] = prediction_counts[i]/sum.to_f
      end
      probs
      {:probs => probs, :num_predictions => sum, :min_confidence => p.min_confidence}
    end
  end
  
  class Crossvalidation
    
    def perform_cv ( task=nil )
      create_cv_datasets( OpenTox::SubTask.create(task, 0, 33) )
      perform_cv_validations( OpenTox::SubTask.create(task, 33, 100) )
    end
    
    def clean_loo_files( delete_feature_datasets )
      Validation.find( :crossvalidation_id => self.id, :validation_type => "crossvalidation" ).each do |v|
        LOGGER.debug "loo-cleanup> delete training dataset "+v.training_dataset_uri
        OpenTox::RestClientWrapper.delete v.training_dataset_uri,subjectid
        if (delete_feature_datasets)
          begin
            model = OpenTox::Model::Generic.find(v.model_uri)
            if model.metadata[OT.featureDataset]
              LOGGER.debug "loo-cleanup> delete feature dataset "+model.metadata[OT.featureDataset]
              OpenTox::RestClientWrapper.delete model.metadata[OT.featureDataset],subjectid
            end
          rescue
          end
        end
      end
    end
    
    # deletes a crossvalidation, all validations are deleted as well
    def delete_crossvalidation
      validations = Validation.find(:crossvalidation_id => self.id) 
      Thread.new do # do deleting in background to not cause a timeout
        validations.each do |v|
          v.subjectid = self.subjectid
          LOGGER.debug "deleting cv-validation "+v.validation_uri.to_s
          v.delete_validation
          sleep 1 if AA_SERVER # wait a second to not stress the a&a service too much
        end
      end
      self.delete
      if (subjectid)
        Thread.new do
          begin
            res = OpenTox::Authorization.delete_policies_from_uri(crossvalidation_uri, subjectid)
            LOGGER.debug "Deleted crossvalidation policy: #{res}"
          rescue
            LOGGER.warn "Policy delete error for crossvalidation: #{crossvalidation_uri}"
          end
        end
      end
      "Successfully deleted crossvalidation "+self.id.to_s+"."
    end
    
    # creates the cv folds
    def create_cv_datasets( task=nil )
      if self.loo=="true"
        orig_dataset = Lib::DatasetCache.find(self.dataset_uri,self.subjectid)
        self.num_folds = orig_dataset.compounds.size
        self.random_seed = 0
        self.stratified = "false"
      else
        self.random_seed = 1 unless self.random_seed
        self.num_folds = 10 unless self.num_folds
        self.stratified = "false" unless self.stratified
      end
      if copy_cv_datasets()
        # dataset folds of a previous crossvalidaiton could be used 
        task.progress(100) if task
      else
        create_new_cv_datasets( task )
      end
    end
    
    # executes the cross-validation (build models and validates them)
    def perform_cv_validations( task=nil )
      
      LOGGER.debug "perform cv validations"
      i = 0
      task_step = 100 / self.num_folds.to_f;
      @tmp_validations.each do | val |
        validation = Validation.create val
        validation.subjectid = self.subjectid
        validation.validate_algorithm( OpenTox::SubTask.create(task, i * task_step, ( i + 1 ) * task_step) )
        raise "validation '"+validation.validation_uri+"' for crossvaldation could not be finished" unless 
          validation.finished
        i += 1
        LOGGER.debug "fold "+i.to_s+" done: "+validation.validation_uri.to_s
      end
      
#      self.attributes = { :finished => true }
#      self.save!
      #self.save if self.new?
      self.finished = true
      self.save
    end
    
    private
    # copies datasets from an older crossvalidation on the same dataset and the same folds
    # returns true if successfull, false otherwise
    def copy_cv_datasets( )
      # for downwards compatibilty: search prediction_feature=nil is ok
      cvs = Crossvalidation.find( { 
        :dataset_uri => self.dataset_uri, 
        :num_folds => self.num_folds, 
        :stratified => self.stratified, 
        :random_seed => self.random_seed,
        :loo => self.loo,
        :finished => true} ).reject{ |cv| (cv.id == self.id || 
                                          (cv.prediction_feature && 
                                           cv.prediction_feature != self.prediction_feature)) }
      cvs.each do |cv|
        next if AA_SERVER and !OpenTox::Authorization.authorized?(cv.crossvalidation_uri,"GET",self.subjectid)
        tmp_val = []
        Validation.find( :crossvalidation_id => cv.id, :validation_type => "crossvalidation" ).each do |v|
          break unless 
            v.prediction_feature == prediction_feature and
            OpenTox::Dataset.exist?(v.training_dataset_uri,self.subjectid) and 
            OpenTox::Dataset.exist?(v.test_dataset_uri,self.subjectid)
          #make sure self.id is set
          #self.save if self.new?
          tmp_val << { :validation_type => "crossvalidation",
                       :training_dataset_uri => v.training_dataset_uri, 
                       :test_dataset_uri => v.test_dataset_uri,
                       :test_target_dataset_uri => self.dataset_uri,
                       :crossvalidation_id => self.id,
                       :crossvalidation_fold => v.crossvalidation_fold,
                       :prediction_feature => prediction_feature,
                       :algorithm_uri => self.algorithm_uri,
                       :algorithm_params => self.algorithm_params }
        end
        if tmp_val.size == self.num_folds.to_i
          @tmp_validations = tmp_val
          LOGGER.debug "copied dataset uris from cv "+cv.crossvalidation_uri.to_s #+":\n"+tmp_val.inspect
          return true
        end
      end
      false
    end
    
    # creates cv folds (training and testdatasets)
    # stores uris in validation objects 
    def create_new_cv_datasets( task = nil )
      LOGGER.debug "creating datasets for crossvalidation"
      orig_dataset = Lib::DatasetCache.find(self.dataset_uri,self.subjectid)
      raise OpenTox::NotFoundError.new "Dataset not found: "+self.dataset_uri.to_s unless orig_dataset
      
      train_dataset_uris = []
      test_dataset_uris = []
      
      meta = { DC.creator => self.crossvalidation_uri }
      case stratified
      when "anti"
         raise "anti-stratification not yet supported for cv"
      when "false"
        if self.loo=="true"
          shuffled_compounds = orig_dataset.compounds
        else
          shuffled_compounds = orig_dataset.compounds.shuffle( self.random_seed )
        end  
        split_compounds = shuffled_compounds.chunk( self.num_folds.to_i )
        LOGGER.debug "cv: num instances for each fold: "+split_compounds.collect{|c| c.size}.join(", ")
          
        self.num_folds.to_i.times do |n|
          test_compounds = []
          train_compounds = []
          self.num_folds.to_i.times do |nn|
            compounds = split_compounds[nn]
            if n == nn
              compounds.each{ |compound| test_compounds << compound}
            else
              compounds.each{ |compound| train_compounds << compound}
            end 
          end
          raise "internal error, num test compounds not correct,"+
            " is '#{test_compounds.size}', should be '#{(shuffled_compounds.size/self.num_folds.to_i)}'" unless 
            (shuffled_compounds.size/self.num_folds.to_i - test_compounds.size).abs <= 1 
          raise "internal error, num train compounds not correct, should be '"+(shuffled_compounds.size-test_compounds.size).to_s+
            "', is '"+train_compounds.size.to_s+"'" unless shuffled_compounds.size - test_compounds.size == train_compounds.size
          datasetname = 'dataset fold '+(n+1).to_s+' of '+self.num_folds.to_s        
          meta[DC.title] = "training "+datasetname 
          LOGGER.debug "training set: "+datasetname+"_train, compounds: "+train_compounds.size.to_s
          train_dataset_uri = orig_dataset.split( train_compounds, orig_dataset.features.keys, 
            meta, self.subjectid ).uri
          train_dataset_uris << train_dataset_uri
          meta[DC.title] = "test "+datasetname
          LOGGER.debug "test set:     "+datasetname+"_test, compounds: "+test_compounds.size.to_s
          test_features = orig_dataset.features.keys.dclone - [self.prediction_feature]
          test_dataset_uri = orig_dataset.split( test_compounds, test_features, 
            meta, self.subjectid ).uri
          test_dataset_uris << test_dataset_uri
        end
      when /true|super/
        if stratified=="true"
          features = [ self.prediction_feature ] 
        else
          features = nil
        end
        r_util = OpenTox::RUtil.new 
        train_datasets, test_datasets = r_util.stratified_k_fold_split(orig_dataset,meta,
          "NA",self.num_folds.to_i,@subjectid,self.random_seed, features)
        r_util.quit_r
        train_dataset_uris = train_datasets.collect{|d| d.uri}
        test_dataset_uris = test_datasets.collect{|d| d.uri}
      else
        raise OpenTox::BadRequestError.new
      end
      
      @tmp_validations = []
      self.num_folds.to_i.times do |n|
        tmp_validation = { :validation_type => "crossvalidation",
                           :training_dataset_uri => train_dataset_uris[n], 
                           :test_dataset_uri => test_dataset_uris[n],
                           :test_target_dataset_uri => self.dataset_uri,
                           :crossvalidation_id => self.id, :crossvalidation_fold => (n+1),
                           :prediction_feature => self.prediction_feature,
                           :algorithm_uri => self.algorithm_uri,
                           :algorithm_params => self.algorithm_params}
        @tmp_validations << tmp_validation
        task.progress( n / self.num_folds.to_f * 100 ) if task
      end
    end
  end
  
  
  module Util
    
    # splits a dataset into test and training dataset via bootstrapping
    # (training dataset-size is n, sampling from orig dataset with replacement)
    # returns map with training_dataset_uri and test_dataset_uri
    def self.bootstrapping( orig_dataset_uri, prediction_feature, subjectid, random_seed=nil, task=nil )
      
      random_seed=1 unless random_seed
      
      orig_dataset = Lib::DatasetCache.find orig_dataset_uri,subjectid
      orig_dataset.load_all
      raise OpenTox::NotFoundError.new "Dataset not found: "+orig_dataset_uri.to_s unless orig_dataset
      if prediction_feature
        raise OpenTox::NotFoundError.new "Prediction feature '"+prediction_feature.to_s+
          "' not found in dataset, features are: \n"+
          orig_dataset.features.inspect unless orig_dataset.features.include?(prediction_feature)
      else
        LOGGER.warn "no prediciton feature given, all features included in test dataset"
      end
      
      compounds = orig_dataset.compounds
      raise OpenTox::NotFoundError.new "Cannot split datset, num compounds in dataset < 2 ("+compounds.size.to_s+")" if compounds.size<2
      
      compounds.each do |c|
        raise OpenTox::NotFoundError.new "Bootstrapping not yet implemented for duplicate compounds" if
          orig_dataset.data_entries[c][prediction_feature].size > 1
      end
      
      srand random_seed.to_i
      while true
        training_compounds = []
        compounds.size.times do
          training_compounds << compounds[rand(compounds.size)]
        end
        test_compounds = []
        compounds.each do |c|
          test_compounds << c unless training_compounds.include?(c)
        end
        if test_compounds.size > 0
          break
        else
          srand rand(10000)
        end
      end
      
      LOGGER.debug "bootstrapping on dataset "+orig_dataset_uri+
                    " into training ("+training_compounds.size.to_s+") and test ("+test_compounds.size.to_s+")"+
                    ", duplicates in training dataset: "+test_compounds.size.to_s
      task.progress(33) if task
      
      result = {}
#      result[:training_dataset_uri] = orig_dataset.create_new_dataset( training_compounds,
#        orig_dataset.features, 
#        "Bootstrapping training dataset of "+orig_dataset.title.to_s, 
#        $sinatra.url_for('/bootstrapping',:full) )
      result[:training_dataset_uri] = orig_dataset.split( training_compounds,
        orig_dataset.features.keys, 
        { DC.title => "Bootstrapping training dataset of "+orig_dataset.title.to_s,
          DC.creator => $url_provider.url_for('/bootstrapping',:full) },
        subjectid ).uri
      task.progress(66) if task

#      result[:test_dataset_uri] = orig_dataset.create_new_dataset( test_compounds,
#        orig_dataset.features.dclone - [prediction_feature], 
#        "Bootstrapping test dataset of "+orig_dataset.title.to_s, 
#        $sinatra.url_for('/bootstrapping',:full) )
      result[:test_dataset_uri] = orig_dataset.split( test_compounds,
        orig_dataset.features.keys.dclone - [prediction_feature],
        { DC.title => "Bootstrapping test dataset of "+orig_dataset.title.to_s,
          DC.creator => $url_provider.url_for('/bootstrapping',:full)} ,
        subjectid ).uri
      task.progress(100) if task
      
      if ENV['RACK_ENV'] =~ /test|debug/
        training_dataset = Lib::DatasetCache.find result[:training_dataset_uri],subjectid
        raise OpenTox::NotFoundError.new "Training dataset not found: '"+result[:training_dataset_uri].to_s+"'" unless training_dataset
        training_dataset.load_all
        value_count = 0
        training_dataset.compounds.each do |c|
          value_count += training_dataset.data_entries[c][prediction_feature].size
        end
        raise  "training compounds error" unless value_count==training_compounds.size
        raise OpenTox::NotFoundError.new "Test dataset not found: '"+result[:test_dataset_uri].to_s+"'" unless 
          Lib::DatasetCache.find result[:test_dataset_uri], subjectid
      end
      LOGGER.debug "bootstrapping done, training dataset: '"+result[:training_dataset_uri].to_s+"', test dataset: '"+result[:test_dataset_uri].to_s+"'"
      
      return result
    end    
    
    # splits a dataset into test and training dataset
    # returns map with training_dataset_uri and test_dataset_uri
    def self.train_test_dataset_split( orig_dataset_uri, prediction_feature, subjectid, stratified="false", split_ratio=nil, random_seed=nil, task=nil )
      split_ratio=0.67 unless split_ratio
      split_ratio = split_ratio.to_f
      random_seed=1 unless random_seed
      random_seed = random_seed.to_i
      
      raise OpenTox::NotFoundError.new "Split ratio invalid: "+split_ratio.to_s unless split_ratio and split_ratio=split_ratio.to_f
      raise OpenTox::NotFoundError.new "Split ratio not >0 and <1 :"+split_ratio.to_s unless split_ratio>0 && split_ratio<1
      orig_dataset = Lib::DatasetCache.find orig_dataset_uri, subjectid
      orig_dataset.load_all subjectid
      raise OpenTox::NotFoundError.new "Dataset not found: "+orig_dataset_uri.to_s unless orig_dataset
      if prediction_feature
        raise OpenTox::NotFoundError.new "Prediction feature '"+prediction_feature.to_s+
          "' not found in dataset, features are: \n"+
          orig_dataset.features.keys.inspect unless orig_dataset.features.include?(prediction_feature)
      else
        LOGGER.warn "no prediciton feature given, all features will be included in test dataset"
      end
      
      meta = { DC.creator => $url_provider.url_for('/training_test_split',:full) }
      
      case stratified
      when /true|super|anti/
        if stratified=="true"
          raise OpenTox::BadRequestError.new "prediction feature required for stratified splits" unless prediction_feature
          features = [prediction_feature]
        else
          LOGGER.warn "prediction feature is ignored for super- or anti-stratified splits" if prediction_feature
          features = nil
        end
        r_util = OpenTox::RUtil.new 
        train, test = r_util.stratified_split( orig_dataset, meta, "NA", split_ratio, @subjectid, random_seed, features, stratified=="anti" )
        r_util.quit_r
        result = {:training_dataset_uri => train.uri, :test_dataset_uri => test.uri}
      when "false"
        compounds = orig_dataset.compounds
        raise OpenTox::BadRequestError.new "Cannot split datset, num compounds in dataset < 2 ("+compounds.size.to_s+")" if compounds.size<2
        split = (compounds.size*split_ratio).to_i
        split = [split,1].max
        split = [split,compounds.size-2].min
        LOGGER.debug "splitting dataset "+orig_dataset_uri+
                    " into train:0-"+split.to_s+" and test:"+(split+1).to_s+"-"+(compounds.size-1).to_s+
                    " (shuffled with seed "+random_seed.to_s+")"
        compounds.shuffle!( random_seed )
        training_compounds = compounds[0..split]
        test_compounds = compounds[(split+1)..-1]
        task.progress(33) if task
  
        meta[DC.title] = "Training dataset split of "+orig_dataset.uri
        result = {}
        result[:training_dataset_uri] = orig_dataset.split( training_compounds,
          orig_dataset.features.keys, meta, subjectid ).uri
        task.progress(66) if task
  
        meta[DC.title] = "Test dataset split of "+orig_dataset.uri
        result[:test_dataset_uri] = orig_dataset.split( test_compounds,
          orig_dataset.features.keys.dclone - [prediction_feature], meta, subjectid ).uri
        task.progress(100) if task  
        
        if ENV['RACK_ENV'] =~ /test|debug/
          raise OpenTox::NotFoundError.new "Training dataset not found: '"+result[:training_dataset_uri].to_s+"'" unless 
            Lib::DatasetCache.find(result[:training_dataset_uri],subjectid)
          test_data = Lib::DatasetCache.find result[:test_dataset_uri],subjectid
          raise OpenTox::NotFoundError.new "Test dataset not found: '"+result[:test_dataset_uri].to_s+"'" unless test_data 
          test_data.load_compounds subjectid
          raise "Test dataset num coumpounds != "+(compounds.size-split-1).to_s+", instead: "+
            test_data.compounds.size.to_s+"\n"+test_data.to_yaml unless test_data.compounds.size==(compounds.size-1-split)
        end
        LOGGER.debug "split done, training dataset: '"+result[:training_dataset_uri].to_s+"', test dataset: '"+result[:test_dataset_uri].to_s+"'"
      else
        raise OpenTox::BadRequestError.new "stratified != false|true|super, is #{stratified}"
      end
      result
    end
  
  end

end

