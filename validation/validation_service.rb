

require "./lib/validation_db.rb"
require "./lib/ot_predictions.rb"

require "./validation/validation_format.rb"


class Array
  
  # cuts an array into <num-pieces> chunks
  def chunk(pieces)
    q, r = length.divmod(pieces)
    res = self.each_slice(q).collect{|a| a}
    if (r!=0)
      leftover = res[pieces..-1].flatten
      res = res[0..(pieces-1)]
      leftover.size.times do |i|
        res[i] << leftover[i]
      end
    end
    res
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
        crossvalidation = Crossvalidation[cv_id]
        resource_not_found_error "Crossvalidation '#{cv_id}' not found." unless crossvalidation
        bad_request_error "Crossvalidation '"+cv_id.to_s+"' not finished" unless crossvalidation.finished
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
        to_delete = [:model_uri, :training_dataset_uri, :test_dataset_uri, :prediction_dataset_uri ]
        case self.validation_type
        when "test_set_validation"
          to_delete -= [ :model_uri, :training_dataset_uri, :test_dataset_uri ]
        when "bootstrapping"
          to_delete -= []
        when "training_test_validation"
          to_delete -=  [ :training_dataset_uri, :test_dataset_uri ]
        when "training_test_split"
          to_delete -= []
        when "validate_datasets"
          to_delete = []
        when "crossvalidation"
          to_delete -= []
        when "crossvalidation_statistics"
          to_delete = []
        else
          internal_server_error "unknown validation type '"+self.validation_type.to_s+"'"
        end
        Thread.new do # do deleting in background to not cause a timeout
          to_delete.each do |attr|
            uri = self.send(attr)
            $logger.debug "also deleting "+attr.to_s+" : "+uri.to_s if uri
            begin
              OpenTox::RestClientWrapper.delete(uri, :subjectid => subjectid) if uri
              sleep 1 if $aa[:uri] # wait a second to not stress the a&a service too much
            rescue => ex
              $logger.warn "could not delete "+uri.to_s+" : "+ex.message.to_s
            end
          end
        end
      end
      self.delete
      if (subjectid)
        Thread.new do
          begin
            res = OpenTox::Authorization.delete_policies_from_uri(validation_uri, subjectid)
            $logger.debug "Deleted validation policy: #{res}"
          rescue
            $logger.warn "Policy delete error for validation: #{validation_uri}"
          end
        end
      end
      "Successfully deleted validation "+self.id.to_s+"."
    end
    
    # validates an algorithm by building a model and validating this model
    def validate_algorithm( task=nil )
      internal_server_error "validation_type missing" unless self.validation_type
      bad_request_error "no algorithm uri: '"+self.algorithm_uri.to_s+"'" if self.algorithm_uri==nil or self.algorithm_uri.to_s.size<1
      
      params = { :dataset_uri => self.training_dataset_uri, :prediction_feature => self.prediction_feature }
      if (self.algorithm_params!=nil)
        self.algorithm_params.split(";").each do |alg_params|
          alg_param = alg_params.split("=",2)
          bad_request_error "invalid algorithm param: '"+alg_params.to_s+"'" unless alg_param.size==2 or alg_param[0].to_s.size<1 or alg_param[1].to_s.size<1
          $logger.warn "algorihtm param contains empty space, encode? "+alg_param[1].to_s if alg_param[1] =~ /\s/
          params[alg_param[0].to_sym] = alg_param[1]
        end
      end
      
      #$logger.warn "running alg"
      #$logger.warn algorithm_uri
      #$logger.warn params.inspect
      self.model_uri = OpenTox::Algorithm.new(algorithm_uri).run(params)
      #$logger.warn "algorithm run finished"
      #$logger.warn "#{result}"
      
      #algorithm = OpenTox::Algorithm::Generic.new(algorithm_uri)
      #params[:subjectid] = subjectid
      #self.model_uri = algorithm.run(params, OpenTox::SubTask.create(task, 0, 33))
      
      #model = OpenTox::Model::PredictionModel.build(algorithm_uri, params, 
      #  OpenTox::SubTask.create(task, 0, 33) )
      
      internal_server_error "model building failed" unless model_uri
      #self.attributes = { :model_uri => model_uri }
      #self.save!
      
#      self.save if self.new?
#      self.update :model_uri => model_uri
      
      #internal_server_error "error after building model: model.dependent_variable != validation.prediciton_feature ("+
      #  model.dependentVariables.to_s+" != "+self.prediction_feature+")" if self.prediction_feature!=model.dependentVariables
          
      validate_model OpenTox::SubTask.create(task, 33, 100)
    end
    
    # validates a model
    # PENDING: a new dataset is created to store the predictions, this should be optional: delete predictions afterwards yes/no
    def validate_model( task=nil )
      
      internal_server_error "validation_type missing" unless self.validation_type
      $logger.debug "validating model '"+self.model_uri+"'"
      
      #model = OpenTox::Model::PredictionModel.find(self.model_uri)
      #resource_not_found_error "model not found: "+self.model_uri.to_s unless model
      model = OpenTox::Model.new(self.model_uri, self.subjectid)
      model.get
      
      unless self.algorithm_uri
        self.algorithm_uri = model.metadata[OT.algorithm.to_s]
      end
      if self.prediction_feature.to_s.size==0
        dependentVariables = model.metadata[OT.dependentVariables.to_s]
        internal_server_error "model has no dependentVariables specified, please give prediction_feature for model validation" unless dependentVariables
        self.prediction_feature = model.metadata[OT.dependentVariables.to_s]
      end
      
      prediction_dataset_uri = ""
      benchmark = Benchmark.measure do 
        #prediction_dataset_uri = model.predict_dataset(self.test_dataset_uri, OpenTox::SubTask.create(task, 0, 50))
        prediction_dataset_uri = model.run({:dataset_uri => self.test_dataset_uri, :subjectid => self.subjectid})
          #"text/uri-list",OpenTox::SubTask.create(task, 0, 50))
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
      models = cv_vals.collect{|v| m = OpenTox::Model.new(v.model_uri, subjectid); m.get; m}
      feature_type = models.first.feature_type(subjectid)
      test_dataset_uris = cv_vals.collect{|v| v.test_dataset_uri}
      prediction_feature = cv_vals.first.prediction_feature
      prediction_dataset_uris = cv_vals.collect{|v| v.prediction_dataset_uri}
      predicted_variables = models.collect{|m| m.predicted_variable(subjectid)}
      predicted_confidences = models.collect{|m| m.predicted_confidence(subjectid)}
      p_data = Lib::PredictionData.create( feature_type, test_dataset_uris, prediction_feature, 
        prediction_dataset_uris, predicted_variables, predicted_confidences, subjectid, waiting_task )
      self.prediction_data = p_data.data
      p_data.data
    end
    
    def compute_prediction_data_with_model(model=nil, task=nil)
      #model = OpenTox::Model::Generic.find(self.model_uri, self.subjectid) if model==nil and self.model_uri
      #resource_not_found_error "model not found: "+self.model_uri.to_s unless model
      model = OpenTox::Model.new(self.model_uri, self.subjectid) if model==nil
      model.get
            
      feature_type = model.feature_type(self.subjectid)
      dependentVariables = model.metadata[OT.dependentVariables.to_s]
      prediction_feature = self.prediction_feature ? nil : dependentVariables
      algorithm_uri = self.algorithm_uri ? nil : model.metadata[OT.algorithm.to_s]
      predicted_variable = model.predicted_variable(self.subjectid)
      predicted_confidence = model.predicted_confidence(self.subjectid)
      internal_server_error "cannot determine whether model '"+model.uri.to_s+"' performs classification or regression: '#{feature_type}', "+
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
    
      $logger.debug "computing prediction stats"
      p_data = Lib::PredictionData.create( feature_type, 
        self.test_dataset_uri, self.prediction_feature, 
        self.prediction_dataset_uri, predicted_variable, predicted_confidence, self.subjectid,
        OpenTox::SubTask.create(task, 0, 80) )
      self.prediction_data = p_data.data
      task.progress(100) if task
      p_data.data
    end
    
    def compute_validation_stats( save_stats=true )
      p_data = self.prediction_data
      internal_server_error "compute prediction data before" if p_data==nil
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
        internal_server_error unless self.valid?
      end
    end
    
    def filter_predictions( min_confidence, min_num_predictions, max_num_predictions, prediction=nil )
      self.prediction_data = nil
      self.save
      
      bad_request_error "only supported for classification" if prediction!=nil and classification_statistics==nil
      bad_request_error "illegal confidence value #{min_confidence}" unless 
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
      bad_request_error("illegal prediction value: '"+prediction+"', available: "+
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
        $logger.debug "loo-cleanup> delete training dataset "+v.training_dataset_uri
        OpenTox::RestClientWrapper.delete v.training_dataset_uri,subjectid
        if (delete_feature_datasets)
          begin
            model = OpenTox::Model::Generic.find(v.model_uri)
            if model.metadata[OT.featureDataset.to_s]
              $logger.debug "loo-cleanup> delete feature dataset "+model.metadata[OT.featureDataset.to_s]
              OpenTox::RestClientWrapper.delete model.metadata[OT.featureDataset.to_s],subjectid
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
          $logger.debug "deleting cv-validation "+v.validation_uri.to_s
          v.delete_validation
          sleep 1 if $aa[:uri] # wait a second to not stress the a&a service too much
        end
      end
      self.delete
      if (subjectid)
        Thread.new do
          begin
            res = OpenTox::Authorization.delete_policies_from_uri(crossvalidation_uri, subjectid)
            $logger.debug "Deleted crossvalidation policy: #{res}"
          rescue
            $logger.warn "Policy delete error for crossvalidation: #{crossvalidation_uri}"
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
      
      $logger.debug "perform cv validations"
      i = 0
      task_step = 100 / self.num_folds.to_f;
      @tmp_validations.each do | val |
        validation = Validation.create val
        validation.subjectid = self.subjectid
        validation.validate_algorithm( OpenTox::SubTask.create(task, i * task_step, ( i + 1 ) * task_step) )
        internal_server_error "validation '"+validation.validation_uri+"' for crossvaldation could not be finished" unless 
          validation.finished
        i += 1
        $logger.debug "fold "+i.to_s+" done: "+validation.validation_uri.to_s
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
        next if $aa[:uri] and !OpenTox::Authorization.authorized?(cv.crossvalidation_uri,"GET",self.subjectid)
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
                       :crossvalidation_id => self.id,
                       :crossvalidation_fold => v.crossvalidation_fold,
                       :prediction_feature => prediction_feature,
                       :algorithm_uri => self.algorithm_uri,
                       :algorithm_params => self.algorithm_params }
        end
        if tmp_val.size == self.num_folds.to_i
          @tmp_validations = tmp_val
          $logger.debug "copied dataset uris from cv "+cv.crossvalidation_uri.to_s #+":\n"+tmp_val.inspect
          return true
        end
      end
      false
    end
    
    # creates cv folds (training and testdatasets)
    # stores uris in validation objects 
    def create_new_cv_datasets( task = nil )
      $logger.debug "creating datasets for crossvalidation"
      orig_dataset = Lib::DatasetCache.find(self.dataset_uri,self.subjectid)
      resource_not_found_error "Dataset not found: "+self.dataset_uri.to_s unless orig_dataset
      
      train_dataset_uris = []
      test_dataset_uris = []
      
      meta = { DC.creator => self.crossvalidation_uri }
      case stratified
      when "false"
        if self.loo=="true"
          shuffled_compound_indices = (0..(orig_dataset.compounds.size-1)).to_a
        else
          shuffled_compound_indices = (0..(orig_dataset.compounds.size-1)).to_a.shuffle( self.random_seed )
        end  
        split_compound_indices = shuffled_compound_indices.chunk( self.num_folds.to_i )
        $logger.debug "cv: num instances for each fold: "+split_compound_indices.collect{|c| c.size}.join(", ")
          
        self.num_folds.to_i.times do |n|
          test_compound_indices = []
          train_compound_indices = []
          self.num_folds.to_i.times do |nn|
            compound_indices = split_compound_indices[nn]
            if n == nn
              compound_indices.each{ |compound| test_compound_indices << compound}
            else
              compound_indices.each{ |compound| train_compound_indices << compound}
            end 
          end
          internal_server_error "internal error, num test compounds not correct,"+
            " is '#{test_compound_indices.size}', should be '#{(shuffled_compound_indices.size/self.num_folds.to_i)}'" unless 
            (shuffled_compound_indices.size/self.num_folds.to_i - test_compound_indices.size).abs <= 1 
          internal_server_error "internal error, num train compounds not correct, should be '"+(shuffled_compound_indices.size-test_compound_indices.size).to_s+
            "', is '"+train_compound_indices.size.to_s+"'" unless shuffled_compound_indices.size - test_compound_indices.size == train_compound_indices.size
          datasetname = 'dataset fold '+(n+1).to_s+' of '+self.num_folds.to_s        
          meta[DC.title] = "training "+datasetname 
          $logger.debug "training set: "+datasetname+"_train, compounds: "+train_compound_indices.size.to_s
          train_dataset_uri = orig_dataset.split( train_compound_indices, orig_dataset.features, meta, self.subjectid ).uri
          train_dataset_uris << train_dataset_uri
          meta[DC.title] = "test "+datasetname
          $logger.debug "test set:     "+datasetname+"_test, compounds: "+test_compound_indices.size.to_s
          test_dataset_uri = orig_dataset.split( test_compound_indices, orig_dataset.features, meta, self.subjectid ).uri
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
        bad_request_error
      end
      
      @tmp_validations = []
      self.num_folds.to_i.times do |n|
        tmp_validation = { :validation_type => "crossvalidation",
                           :training_dataset_uri => train_dataset_uris[n], 
                           :test_dataset_uri => test_dataset_uris[n],
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
      resource_not_found_error "Dataset not found: "+orig_dataset_uri.to_s unless orig_dataset
      if prediction_feature
        resource_not_found_error "Prediction feature '"+prediction_feature.to_s+
          "' not found in dataset, features are: \n"+
          orig_dataset.features.inspect unless orig_dataset.features.include?(prediction_feature)
      else
        $logger.warn "no prediciton feature given, all features included in test dataset"
      end
      
      compound_indices = (0..(orig_dataset.compounds.size-1)).to_a
      resource_not_found_error "Cannot split datset, num compounds in dataset < 2 ("+compound_indices.size.to_s+")" if compound_indices.size<2
      
      srand random_seed.to_i
      while true
        training_compound_indices = []
        compound_indices.size.times do
          training_compound_indices << compound_indices[rand(compound_indices.size)]
        end
        test_compound_indices = []
        compound_indices.each do |idx|
          test_compound_indices << idx unless training_compound_indices.include?(idx)
        end
        if test_compound_indices.size > 0
          break
        else
          srand rand(10000)
        end
      end
      
      $logger.debug "bootstrapping on dataset "+orig_dataset_uri+
                    " into training ("+training_compound_indices.size.to_s+") and test ("+test_compound_indices.size.to_s+")"+
                    ", duplicates in training dataset: "+test_compound_indices.size.to_s
      task.progress(33) if task
      
      result = {}
      result[:training_dataset_uri] = orig_dataset.split( training_compound_indices, orig_dataset.features, 
        { DC.title => "Bootstrapping training dataset of "+orig_dataset.title.to_s,
          DC.creator => $url_provider.to('/validation/bootstrapping',:full) },
        subjectid ).uri
      task.progress(66) if task

      result[:test_dataset_uri] = orig_dataset.split( test_compound_indices, orig_dataset.features,
        { DC.title => "Bootstrapping test dataset of "+orig_dataset.title.to_s,
          DC.creator => $url_provider.to('/validation/bootstrapping',:full)} ,
        subjectid ).uri
      task.progress(100) if task
      
      $logger.debug "bootstrapping done, training dataset: '"+result[:training_dataset_uri].to_s+"', test dataset: '"+result[:test_dataset_uri].to_s+"'"
      return result
    end    
    
    # splits a dataset into test and training dataset
    # returns map with training_dataset_uri and test_dataset_uri
    def self.train_test_dataset_split( creator_uri, orig_dataset_uri, prediction_feature, subjectid, stratified="false", split_ratio=nil, random_seed=nil, task=nil )
      
      $logger.debug "train test split"
      
      split_ratio=0.67 unless split_ratio
      split_ratio = split_ratio.to_f
      random_seed=1 unless random_seed
      random_seed = random_seed.to_i
      
      resource_not_found_error "Split ratio invalid: "+split_ratio.to_s unless split_ratio and split_ratio=split_ratio.to_f
      resource_not_found_error "Split ratio not >0 and <1 :"+split_ratio.to_s unless split_ratio>0 && split_ratio<1
      orig_dataset = Lib::DatasetCache.find orig_dataset_uri, subjectid
      resource_not_found_error "Dataset not found: "+orig_dataset_uri.to_s unless orig_dataset
      
      if prediction_feature
        if stratified==/true/
          resource_not_found_error "Prediction feature '"+prediction_feature.to_s+
            "' not found in dataset, features are: \n"+orig_dataset.features.collect{|f| f.uri}.inspect unless orig_dataset.features.include?(prediction_feature)
        else
          $logger.warn "prediction_feature argument is ignored for non-stratified splits" if prediction_feature
          prediction_feature=nil
        end
      elsif stratified==/true/
        bad_request_error "prediction feature required for stratified splits" unless prediction_feature
      end
      
      meta = { DC.creator => creator_uri }
      
      case stratified
      when /true|super/
        if stratified=="true"
          features = [prediction_feature]
        else
          features = nil
        end
        r_util = OpenTox::RUtil.new 
        train, test = r_util.stratified_split( orig_dataset, meta, "NA", split_ratio, @subjectid, random_seed, features )
        r_util.quit_r
        result = {:training_dataset_uri => train.uri, :test_dataset_uri => test.uri}
      when "false"
        compound_indices = (0..(orig_dataset.compounds.size-1)).to_a
        bad_request_error "Cannot split datset, num compounds in dataset < 2 ("+compound_indices.size.to_s+")" if compound_indices.size<2
        split = (compound_indices.size*split_ratio).round
        split = [split,1].max
        split = [split,compound_indices.size-2].min
        $logger.debug "splitting dataset "+orig_dataset_uri+
                    " into train:0-"+split.to_s+" and test:"+(split+1).to_s+"-"+(compound_indices.size-1).to_s+
                    " (shuffled with seed "+random_seed.to_s+")"
        compound_indices.shuffle!( random_seed )
        training_compound_indices = compound_indices[0..(split-1)]
        test_compound_indices = compound_indices[split..-1]
        task.progress(33) if task
  
        meta[DC.title] = "Training dataset split of "+orig_dataset.uri
        result = {}
        train_data = orig_dataset.split( training_compound_indices, orig_dataset.features, meta, subjectid )
        est_num_train_compounds = (orig_dataset.compounds.size*split_ratio).round
        internal_server_error "Train dataset num coumpounds != #{est_num_train_compounds}, instead: "+train_data.compounds.size.to_s unless 
          train_data.compounds.size==est_num_train_compounds
        result[:training_dataset_uri] = train_data.uri
        task.progress(66) if task
  
        meta[DC.title] = "Test dataset split of "+orig_dataset.uri
        test_data = orig_dataset.split( test_compound_indices, orig_dataset.features, meta, subjectid )
        est_num_test_compounds = orig_dataset.compounds.size-est_num_train_compounds
        internal_server_error "Test dataset num coumpounds != #{est_num_test_compounds}, instead: "+test_data.compounds.size.to_s unless 
          test_data.compounds.size==est_num_test_compounds
        result[:test_dataset_uri] = test_data.uri
        task.progress(100) if task  
        
        $logger.debug "split done, training dataset: '"+result[:training_dataset_uri].to_s+"', test dataset: '"+result[:test_dataset_uri].to_s+"'"
      else
        bad_request_error "stratified != false|true|super, is #{stratified}"
      end
      result
    end
  
  end

end

