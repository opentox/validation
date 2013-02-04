
# the variance is computed when merging results for these attributes 
VAL_ATTR_VARIANCE = [ :area_under_roc, :percent_correct, :root_mean_squared_error, :mean_absolute_error, 
  :r_square, :accuracy, :average_area_under_roc, :weighted_accuracy, :weighted_root_mean_squared_error, :weighted_mean_absolute_error, 
  :weighted_r_square  ]
VAL_ATTR_RANKING = [ :area_under_roc, :percent_correct, :true_positive_rate, :true_negative_rate, :average_area_under_roc, :accuracy, :f_measure ]

ATTR_NICE_NAME = {}

class String
  def nice_attr()
    if ATTR_NICE_NAME.has_key?(self)
      return ATTR_NICE_NAME[self]
    else
      return self.to_s.gsub(/_id$/, "").gsub(/_/, " ").capitalize
    end
  end
end


class Object
  
  def to_nice_s
    if is_a?(Float)
      if self==0
        return "0"
      elsif abs>0.1
        return "%.3f" % self
      elsif abs>0.01
        return "%.3f" % self
      else
        return "%.2e" % self
      end
    end
    return collect{ |i| i.to_nice_s  }.join(", ") if is_a?(Array)
    return collect{ |i,j| i.to_nice_s+": "+j.to_nice_s  }.join(", ") if is_a?(Hash)
    return to_s
  end
  
  
  # checks weather an object has equal values as stored in the map
  # example o.att = "a", o.att2 = 12, o.has_values?({ att => a }) is true
  #
  # call-seq:
  #   has_values?(map) => boolean
  # 
  def has_values?(map)
    map.each { |k,v| return false if send(k)!=v }
    return true
  end
end


module Reports
  
  @@validation_access = ValidationDB.new
  @@persistance = ReportService.persistance
  
  def self.persistance
    @@persistance
  end
  
  def self.validation_access
    @@validation_access
  end
  
  # for overwriting validation source (other than using webservices)
  def self.reset_validation_access(validation_access)
    @@validation_access = validation_access
  end
  
  
  # = ReportValidation
  #
  # contains all values of a validation object
  #
  class ReportValidation
    
    def self.resolve_cv_uris(validation_uris, identifier, subjectid)
      Reports.validation_access.resolve_cv_uris(validation_uris, identifier, subjectid)
    end
    
    # create member variables for all validation properties
    @@validation_attributes = Validation::ALL_PROPS + 
      VAL_ATTR_VARIANCE.collect{ |a| (a.to_s+"_variance").to_sym } +
      VAL_ATTR_RANKING.collect{ |a| (a.to_s+"_ranking").to_sym }
    @@validation_attributes.each{ |a| attr_accessor a } 
  
    attr_reader :predictions, :filter_params
    attr_accessor :identifier, :validation_report_uri, :crossvalidation_report_uri, :subjectid
    
    def initialize(uri = nil, filter_params=nil, subjectid = nil)
      Reports.validation_access.init_validation(self, uri, filter_params, subjectid) if uri
      @subjectid = subjectid
      raise unless filter_params==nil || filter_params.is_a?(Hash)
      @filter_params = filter_params
      @created_resources = []
      #raise "subjectid is nil" unless subjectid
    end
    
    def self.from_cv_statistics( cv_uri, filter_params, subjectid )
      v = ReportValidation.new(nil, filter_params, subjectid)
      Reports.validation_access.init_validation_from_cv_statistics(v, cv_uri, filter_params, subjectid)
      v
    end
    
    def training_feature_dataset_uri
      unless @training_feature_dataset
        @training_feature_dataset = Reports.validation_access.training_feature_dataset_uri( self, @subjectid )
      end
      @training_feature_dataset
    end
    
    #hack this does create the features for the test dataset
    def test_feature_dataset_uri
      unless @test_feature_dataset
        @test_feature_dataset = Reports.validation_access.test_feature_dataset_uri( self, @subjectid )
      end
      @test_feature_dataset
    end
    
    # returns/creates predictions, cache to save rest-calls/computation time
    #
    # call-seq:
    #   get_predictions => Predictions
    # 
    def get_predictions( task=nil )
      if @predictions
        task.progress(100) if task
        @predictions
      else
        unless @prediction_dataset_uri
          $logger.info("no predictions available, prediction_dataset_uri not set")
          task.progress(100) if task
          nil
        else
          @predictions = Reports.validation_access.get_predictions( self, @filter_params, @subjectid, task )
        end
      end
    end
    
    # returns the predictions feature values (i.e. the domain of the class attribute)
    #
    def get_accept_values()
      @accept_values = Reports.validation_access.get_accept_values(self, @subjectid) unless @accept_values
      @accept_values
    end
    
    # is classification/regression validation? cache to save rest-calls
    #
    def feature_type
      return @feature_type if @feature_type!=nil
      @feature_type = Reports.validation_access.feature_type(self, @subjectid) 
    end
    
    def predicted_variable
      return @predicted_variable if @predicted_variable!=nil
      @predicted_variable = Reports.validation_access.predicted_variable(self, @subjectid) 
    end
    
    def predicted_confidence
      return @predicted_confidence if @predicted_confidence!=nil
      @predicted_confidence = Reports.validation_access.predicted_confidence(self, @subjectid) 
    end    
    
    # loads all crossvalidation attributes, of the corresponding cv into this object 
    def load_cv_attributes
      raise "crossvalidation-id not set" unless @crossvalidation_id
      Reports.validation_access.init_cv(self, @subjectid)
      # load cv report
      ids = Reports.persistance.list_reports("crossvalidation",{:crossvalidation=>self.crossvalidation_uri.to_s })
      @crossvalidation_report_uri = ReportService.instance.get_uri("crossvalidation",ids[-1]) if ids and ids.size>0
    end
    
    def clone_validation
      new_val = clone
      VAL_ATTR_VARIANCE.each { |a| new_val.send((a.to_s+"_variance=").to_sym,nil) }
      return new_val
    end
  end
  
  # = Reports:ValidationSet
  #
  # contains an array of validations, including some functionality as merging validations..
  #
  class ValidationSet
    
    def initialize(validation_uris=nil, identifier=nil, filter_params=nil, subjectid=nil)
      @unique_values = {}
      @validations = []
      if validation_uris    
        validation_uri_and_ids = ReportValidation.resolve_cv_uris(validation_uris, identifier, subjectid)
        validation_uri_and_ids.each do |u,id|
          v = ReportValidation.new(u, filter_params, subjectid)
          v.identifier = id if id
          ids = Reports.persistance.list_reports("validation",{:validation_uris=>v.validation_uri })
          v.validation_report_uri = ReportService.instance.get_uri("validation",ids[-1]) if ids and ids.size>0
          @validations << v
        end
      end
    end
  
    def self.create(validations)
      set = ValidationSet.new
      validations.each{ |v| set.validations.push(v) }
      set
    end
    
    def get(index)
      return @validations[index]
    end
    
    #def first()
      #return @validations.first
    #end
    
    # returns the values of the validations for __attribute__
    # * if unique is true a set is returned, i.e. not redundant info
    # * => if unique is false the size of the returned array is equal to the number of validations  
    #
    # call-seq:
    #   get_values(attribute, unique=true) => array
    # 
    def get_values(attribute, unique=true)
      a = Array.new
      @validations.each{ |v| a.push(v.send(attribute)) if !unique || a.index(v.send(attribute))==nil } 
      return a
    end
    
    # returns the number of different values that exist for an attribute in the validation set  
    #
    # call-seq:
    #   num_different_values(attribute) => integer
    # 
    def num_different_values(attribute)
      return get_values(attribute).size
    end
    
    # returns true if at least one validation has a nil value for __attribute__  
    #
    # call-seq:
    #   has_nil_values?(attribute) => boolean
    # 
    def has_nil_values?(attribute)
      @validations.each{ |v| return true unless v.send(attribute) } 
      return false
    end
    
    def filter_params
      @validations.first.filter_params
    end
    
    # loads the attributes of the related crossvalidation into all validation objects
    #
    def load_cv_attributes
      @validations.each{ |v| v.load_cv_attributes }
    end
    
    def unique_value(validation_prop)
      return @unique_values[validation_prop] if @unique_values.has_key?(validation_prop)
      val = @validations[0].send(validation_prop)        
      (1..@validations.size-1).each do |i|
          if @validations[i].send(validation_prop)!=val
            val = nil
            break
          end
      end
      @unique_values[validation_prop] = val
      return val
    end
    
#    def get_true_prediction_feature_value
#      if all_classification?
#        class_values = get_accept_values
#        if class_values.size == 2
#          (0..1).each do |i|
#            return class_values[i] if (class_values[i].to_s.downcase == "true" || class_values[i].to_s.downcase == "active")
#          end
#        end
#      end
#      return nil
#    end
    
    def get_accept_values( )
      return unique_value("get_accept_values")
    end
    
    def get_true_accept_value()
      accept_values = get_accept_values()
      if accept_values.size==2
        if (accept_values[0] =~ TRUE_REGEXP and !(accept_values[1] =~ TRUE_REGEXP))
          return accept_values[0]
        elsif (accept_values[1] =~ TRUE_REGEXP and !(accept_values[0] =~ TRUE_REGEXP))
          return accept_values[1]
        end 
      end
      nil
    end
    
    def get_accept_values_for_attr( attribute )
      if !Validation::Validation.classification_property?(attribute)
        []
      else
        accept_values = get_accept_values()
        if !Validation::Validation.depends_on_class_value?(attribute)
          [ nil ]
        elsif accept_values.size==2 and get_true_accept_value()!=nil and Validation::Validation.complement_exists?(attribute)
          [ get_true_accept_value() ]
        else
          accept_values
        end
      end
    end
    
    # checks weather all validations are classification/regression validations
    #
    def unique_feature_type
      return unique_value("feature_type")
    end

    # returns a new set with all validation that have values as specified in the map
    #
    # call-seq:
    #   filter(map) => ValidationSet
    # 
    def filter(map)
      new_set = ValidationSet.new
      validations.each{ |v| new_set.validations.push(v) if v.has_values?(map) }
      return new_set
    end
    
    # returns a new set with all validation that the attached block accepted
    # e.g. create set with predictions: collect{ |validation| validation.get_predictions!=null } 
    #
    # call-seq:
    #   filter_proc(proc) => ValidationSet
    # 
    def collect
      new_set = ValidationSet.new
      validations.each{ |v| new_set.validations.push(v) if yield(v) }
      return new_set
    end
    
    def to_table( attribute_col, attribute_row, attribute_val)
      
      row_values = get_values(attribute_row)
      #puts "row: "+row_values.inspect
      col_values = get_values(attribute_col)
      #puts "col: "+col_values.inspect
      
      # get domain for classification attribute, i.e. ["true","false"]
      accept_values = get_accept_values_for_attr(attribute_val)
      # or the attribute has a complementary value, i.e. true_positive_rate
      # -> domain is reduced to one class value
      first_value_elem = (accept_values.size==1 && accept_values[0]!=nil)
      
      cell_values = {}
      row_values.each do |row|
        col_values.each do |col|
          val = nil
          @validations.each do |v|
            if v.send(attribute_row)==row and v.send(attribute_col)==col
              #raise "two validation have equal row and column values: "+val.to_s if val!=nil
              val = v.send(attribute_val)
              val = val[accept_values[0]] if first_value_elem
              val = val.to_nice_s
            end
          end
          cell_values[row] = [] if cell_values[row]==nil
          cell_values[row] << val
        end
      end
      #puts cell_values.inspect
      
      table = []
      table << [ "" ] + col_values
      row_values.each do |row|
        table << [ row ] + cell_values[row]
      end
      #puts table.inspect
      
      table
    end
    
    # returns an array, with values for __attributes__, that can be use for a table
    # * first row is header row
    # * other rows are values
    #
    # call-seq:
    #   to_array(attributes, remove_nil_attributes) => array
    # 
    def to_array(attributes, remove_nil_attributes=true)
      array = Array.new
      array.push(attributes.collect{|a| a.to_s.nice_attr})
      attribute_not_nil = Array.new(attributes.size)
      @validations.each do |v|
        index = -1
        array.push(attributes.collect do |a|
          index += 1
          if VAL_ATTR_VARIANCE.index(a)
            variance = v.send( (a.to_s+"_variance").to_sym )
          end
          
          #variance = " +- "+variance.to_nice_s if variance
          val = v.send(a)
          if val==nil || val.to_s.chomp.size==0
            ''
          else
            attribute_not_nil[index] = true if remove_nil_attributes
            
            accept_values = get_accept_values_for_attr(a)
            # get domain for classification attribute, i.e. ["true","false"]
            if accept_values.size==1 && accept_values[0]!=nil
              # or the attribute has a complementary value, i.e. true_positive_rate
              # -> domain is reduced to one class value
              raise "illegal state, value for "+a.to_s+" is no hash: '"+val.to_s+"'" unless (val.is_a?(Hash))
              val = val[accept_values[0]]
            end
            
            if variance
              #puts "variance given #{a}, #{val.inspect}, #{val.class}, #{variance.inspect}, #{variance.class}"
              if (val.is_a?(Array))
                raise "not implemented"
              elsif (val.is_a?(Hash))
                val.collect{ |i,j| i.to_nice_s+": "+j.to_nice_s + " +- " +
                  variance[i].to_nice_s  }.join(", ")
              else
                if (variance.is_a?(Hash))
                  raise "invalid variance" unless accept_values.size==1 && accept_values[0]!=nil
                  variance = variance[accept_values[0]]
                end
                val.to_nice_s + " +- " + variance.to_nice_s
              end
            else
              val.to_nice_s
            end
          end
        end)
      end

      if remove_nil_attributes #delete in reverse order to avoid shifting of indices
        (0..attribute_not_nil.size-1).to_a.reverse.each do |i|
          array.each{|row| row.delete_at(i)} unless attribute_not_nil[i]
        end
      end
      
      return array
    end
    
    def replace_with_cv_stats
      new_set = ValidationSet.new
      grouping = Util.group(@validations, [:crossvalidation_id])
      grouping.each do |g|
        v = ReportValidation.from_cv_statistics(g[0].crossvalidation_uri, @validations.first.filter_params, g[0].subjectid)
        v.identifier = g.collect{|vv| vv.identifier}.uniq.join(";")
        new_set.validations << v 
      end
      return new_set
    end
    
    # creates a new validaiton set, that contains merged validations
    # all validation with equal values for __equal_attributes__ are summed up in one validation, i.e. merged 
    #
    # call-seq:
    #   to_array(attributes) => array
    # 
    def merge(equal_attributes)
      new_set = ValidationSet.new
      
      # unique values stay unique when merging
      # derive unique values before, because model dependent props cannot be accessed later (when mergin validations from different models)
      new_set.unique_values = @unique_values
      
      #compute grouping
      grouping = Util.group(@validations, equal_attributes)
      #puts "groups "+grouping.size.to_s

      #merge
      Lib::MergeObjects.register_merge_attributes( ReportValidation,
        Validation::VAL_MERGE_AVG+Validation::VAL_MERGE_SUM,[],
        Validation::VAL_MERGE_GENERAL+[:identifier, :validation_report_uri, :crossvalidation_report_uri, :subjectid]) unless 
          Lib::MergeObjects.merge_attributes_registered?(ReportValidation)
      grouping.each do |g|
        new_set.validations << g[0].clone_validation
        g[1..-1].each do |v|
          new_set.validations[-1] = Lib::MergeObjects.merge_objects(new_set.validations[-1],v)
        end
      end
      return new_set
    end
    
    def sort(attributes, ascending=true)
      attributes = [attributes] unless attributes.is_a?(Array)
      @validations.sort! do |a,b|
        val = 0
        attributes.each do |attr|
          if a.send(attr).to_s != b.send(attr).to_s
            val = a.send(attr).to_s <=> b.send(attr).to_s
            break
          end
        end
        val
      end
    end
    
    # creates a new validaiton set, that contains a ranking for __ranking_attribute__
    # (i.e. for ranking attribute :acc, :acc_ranking is calculated)
    # all validation with equal values for __equal_attributes__ are compared
    # (the one with highest value of __ranking_attribute__ has rank 1, and so on) 
    #
    # call-seq:
    #   compute_ranking(equal_attributes, ranking_attribute) => array
    # 
    def compute_ranking(equal_attributes, ranking_attribute, class_value=nil )
      
      #puts "compute_ranking("+equal_attributes.inspect+", "+ranking_attribute.inspect+", "+class_value.to_s+" )"
      new_set = ValidationSet.new
      (0..@validations.size-1).each do |i|
        new_set.validations.push(@validations[i].clone_validation)
      end
      
      grouping = Util.group(new_set.validations, equal_attributes)
      grouping.each do |group|
  
        # put indices and ranking values for current group into hash
        rank_hash = {}
        (0..group.size-1).each do |i|
          val = group[i].send(ranking_attribute)
          if val.is_a?(Hash)
            if class_value != nil
              raise "no value for class value "+class_value.class.to_s+" "+class_value.to_s+" in hash "+val.inspect.to_s unless val.has_key?(class_value)
              val = val[class_value]
            else
              raise "value for '"+ranking_attribute.to_s+"' is a hash, specify class value plz"
            end
          end
          rank_hash[i] = val
        end
        #puts rank_hash.inspect
              
        # sort group accrording to second value (= ranking value)
        rank_array = rank_hash.sort { |a, b| b[1] <=> a[1] } 
        #puts rank_array.inspect
        
        # create ranks array
        ranks = Array.new
        (0..rank_array.size-1).each do |j|
          
          val = rank_array.at(j)[1]
          rank = j+1
          ranks.push(rank.to_f)
          
          # check if previous ranks have equal value
          equal_count = 1;
          equal_rank_sum = rank;
          
          while ( j - equal_count >= 0 && (val - rank_array.at(j - equal_count)[1]).abs < 0.0001 )
            equal_rank_sum += ranks.at(j - equal_count);
            equal_count += 1;
          end
          
          # if previous ranks have equal values -> replace with avg rank
          if (equal_count > 1)
            (0..equal_count-1).each do |k|
              ranks[j-k] = equal_rank_sum / equal_count.to_f;            
            end
          end
        end
        #puts ranks.inspect
        
        # set rank as validation value
        (0..rank_array.size-1).each do |j|
          index = rank_array.at(j)[0]
          group[index].send( (ranking_attribute.to_s+"_ranking=").to_sym, ranks[j])
        end
      end
      
      return new_set
    end
    
    def size
      return @validations.size
    end
    
    def validations
      @validations
    end
    
    protected
    def unique_values=(unique_values)
      @unique_values = unique_values
    end
  end
  
end 
