
module Lib

  module Util
    
    def self.compute_variance( old_variance, n, new_mean, old_mean, new_value )
      # use revursiv formular for computing the variance
      # ( see Tysiak, Folgen: explizit und rekursiv, ISSN: 0025-5866
      #  http://www.frl.de/tysiakpapers/07_TY_Papers.pdf )
      return (n>1 ? old_variance * (n-2)/(n-1) : 0) +
             (new_mean - old_mean)**2 +
             (n>1 ? (new_value - new_mean)**2/(n-1) : 0 )
    end
  end
  
  class Predictions
  
    def identifier(instance_index)
      return instance_index.to_s
    end
  
    def initialize( predicted_values, 
                    actual_values, 
                    confidence_values, 
                    feature_type, 
                    accept_values=nil )
                    
      @predicted_values = predicted_values
      @actual_values = actual_values
      @confidence_values = confidence_values
      @feature_type = feature_type
      @accept_values = accept_values
      @num_classes = 1
      
      #puts "predicted:  "+predicted_values.inspect
      #puts "actual:     "+actual_values.inspect
      #puts "confidence: "+confidence_values.inspect
      
      raise "unknown feature_type: '"+@feature_type.to_s+"'" unless 
        @feature_type=="classification" || @feature_type=="regression"
      raise "no predictions" if @predicted_values.size == 0
      num_info = "predicted:"+@predicted_values.size.to_s+
        " confidence:"+@confidence_values.size.to_s+" actual:"+@actual_values.size.to_s
      raise "illegal num actual values "+num_info if  @actual_values.size != @predicted_values.size
      raise "illegal num confidence values "+num_info if  @confidence_values.size != @predicted_values.size
      
      @confidence_values.each{ |c| raise "illegal confidence value: '"+c.to_s+"'" unless c==nil or (c.is_a?(Numeric) and c>=0 and c<=1) }
      
      case @feature_type
      when "classification"
        raise "accept_values missing while performing classification" unless @accept_values
        @num_classes = @accept_values.size
        raise "num classes < 2" if @num_classes<2
        { "predicted"=>@predicted_values, "actual"=>@actual_values }.each do |s,values|
          values.each{ |v| raise "illegal "+s+" classification-value ("+v.to_s+"),"+
            "has to be either nil or index of predicted-values" if v!=nil and (!v.is_a?(Numeric) or v<0 or v>@num_classes)}
        end
      when "regresssion"
        raise "accept_values != nil while performing regression" if @accept_values
        { "predicted"=>@predicted_values, "actual"=>@actual_values }.each do |s,values|
          values.each{ |v| raise "illegal "+s+" regression-value ("+v.to_s+"),"+
            "has to be either nil or number (not NaN, not Infinite)" if v!=nil and (!v.is_a?(Numeric) or v.nan? or v.finite?)}
        end
      end
      
      init_stats()
      (0..@predicted_values.size-1).each do |i|
        update_stats( @predicted_values[i], @actual_values[i], @confidence_values[i] )
      end
    end
    
    def init_stats
      @conf_provided = false
      
      @num_no_actual_value = 0
      @num_with_actual_value = 0 
      
      @num_predicted = 0
      @num_unpredicted = 0
      
      @mean_confidence = 0
      
      case @feature_type
      when "classification"
        
        # confusion-matrix will contain counts for predictions in a 2d array:
        # index of first dim: actual values
        # index of second dim: predicited values
        # example: 
        # * summing up over all i with fixed n
        # * confusion_matrix[i][n]
        # * will give the number of instances that are predicted as n
        @confusion_matrix = []
        @accept_values.each do |v|
          @confusion_matrix.push( Array.new( @num_classes, 0 ) )
        end
        
        @num_correct = 0
        @num_incorrect = 0
      when "regression"
        @sum_error = 0
        @sum_abs_error = 0
        @sum_squared_error = 0
        
        @prediction_mean = 0
        @actual_mean = 0
        
        @variance_predicted = 0
        @variance_actual = 0
        
        @sum_actual = 0
        @sum_predicted = 0
        @sum_multiply = 0
        @sum_squares_actual = 0
        @sum_squares_predicted = 0
        
        @sum_weighted_abs_error = 0
        @sum_weighted_squared_error = 0
      end
    end
    
    def update_stats( predicted_value, actual_value, confidence_value )
      
      if actual_value==nil
        @num_no_actual_value += 1
      else 
        @num_with_actual_value += 1
        
        if predicted_value==nil
          @num_unpredicted += 1
        else
          @num_predicted += 1
          
          @conf_provided |= confidence_value!=nil
          @mean_confidence = (confidence_value + @mean_confidence*(@num_predicted-1)) / @num_predicted.to_f if @conf_provided
          
          case @feature_type
          when "classification"
            @confusion_matrix[actual_value][predicted_value] += 1
            if (predicted_value == actual_value)
              @num_correct += 1
            else
              @num_incorrect += 1
            end
          when "regression"
            delta = predicted_value - actual_value
            @sum_error += delta
            @sum_abs_error += delta.abs
            @sum_weighted_abs_error += delta.abs*confidence_value if @conf_provided
            @sum_squared_error += delta**2
            @sum_weighted_squared_error += (delta**2)*confidence_value if @conf_provided
            
            old_prediction_mean = @prediction_mean
            @prediction_mean = (@prediction_mean * (@num_predicted-1) + predicted_value) / @num_predicted.to_f
            old_actual_mean = @actual_mean
            @actual_mean = (@actual_mean * (@num_predicted-1) + actual_value) / @num_predicted.to_f

            @variance_predicted = Util.compute_variance( @variance_predicted, @num_predicted, 
              @prediction_mean, old_prediction_mean, predicted_value )
            @variance_actual = Util.compute_variance( @variance_actual, @num_predicted, 
              @actual_mean, old_actual_mean, actual_value )
              
            @sum_actual += actual_value
            @sum_predicted += predicted_value
            @sum_multiply += (actual_value*predicted_value)
            @sum_squares_actual += actual_value**2
            @sum_squares_predicted += predicted_value**2
          end
        end
      end
    end
    
    def percent_correct
      raise "no classification" unless @feature_type=="classification"
      pct = 100 * @num_correct / (@num_with_actual_value - @num_unpredicted).to_f
      pct.nan? ? 0 : pct 
    end
    
    def percent_incorrect
      raise "no classification" unless @feature_type=="classification"
      return 0 if @num_with_actual_value==0
      return 100 * @num_incorrect / (@num_with_actual_value - @num_unpredicted).to_f
    end
    
    def accuracy
      acc = percent_correct / 100.0
      acc.nan? ? 0 : acc
    end
    
    def weighted_accuracy
      return 0 unless confidence_values_available?      
      raise "no classification" unless @feature_type=="classification"
      total = 0
      correct = 0
      (0..@predicted_values.size-1).each do |i|
        if @predicted_values[i]!=nil
          total += @confidence_values[i]
          correct += @confidence_values[i] if @actual_values[i]==@predicted_values[i]
        end
      end
      if total==0 || correct == 0
        return 0  
      else
        return correct / total 
      end
    end

    def percent_unpredicted
      return 0 if @num_with_actual_value==0
      return 100 * @num_unpredicted / @num_with_actual_value.to_f
    end

    def num_unpredicted
      @num_unpredicted
    end

    def percent_without_class
      return 0 if @predicted_values==0
      return 100 * @num_no_actual_value / @predicted_values.size.to_f
    end
    
    def num_without_class
      @num_no_actual_value
    end

    def num_correct
      raise "no classification" unless @feature_type=="classification"
      return @num_correct
    end

    def num_incorrect
      raise "no classification" unless @feature_type=="classification"
      return @num_incorrect
    end
    
    def num_unclassified
      raise "no classification" unless @feature_type=="classification"
      return @num_unpredicted
    end
    
    # internal structure of confusion matrix:
    # hash with keys: hash{ :confusion_matrix_actual => <class_value>, :confusion_matrix_predicted => <class_value> }
    #     and values: <int-value>
    def confusion_matrix
      
      raise "no classification" unless @feature_type=="classification"
      res = {}
      (0..@num_classes-1).each do |actual|
          (0..@num_classes-1).each do |predicted|
            res[{:confusion_matrix_actual => @accept_values[actual],
                 :confusion_matrix_predicted => @accept_values[predicted]}] = @confusion_matrix[actual][predicted]
        end
      end
      return res
    end
    
    # does only take the instances that are classified as <class-index> into account
    def area_under_roc(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| area_under_roc(i) } ) if 
        class_index==nil
      return 0 unless confidence_values_available?
      
      LOGGER.warn("TODO: implement approx computiation of AUC,"+
        "so far Wilcoxon-Man-Whitney is used (exponential)") if 
        @predicted_values.size>1000
      #puts "COMPUTING AUC "+class_index.to_s
      
      tp_conf = []
      fp_conf = []
      (0..@predicted_values.size-1).each do |i|
        if @predicted_values[i]==class_index
          if @actual_values[i]==@predicted_values[i]
            tp_conf.push(@confidence_values[i])
          else
            fp_conf.push(@confidence_values[i])
          end
        end
      end
      #puts tp_conf.inspect+"\n"+fp_conf.inspect+"\n\n"
      
      return 0.0 if tp_conf.size == 0
      return 1.0 if fp_conf.size == 0
      sum = 0
      tp_conf.each do |tp|
        fp_conf.each do |fp|
          sum += 1 if tp>fp
          sum += 0.5 if tp==fp
        end
      end
      return sum / (tp_conf.size * fp_conf.size).to_f
    end
    
    def f_measure(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| f_measure(i) } ) if class_index==nil
      
      prec = precision(class_index)
      rec = recall(class_index)
      return 0 if prec == 0 and rec == 0
      return 2 * prec * rec / (prec + rec).to_f;
    end
    
    def precision(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| precision(i) } ) if class_index==nil
      
      correct = 0 # all instances with prediction class_index that are correctly classified 
      total = 0 # all instances with prediciton class_index
      (0..@num_classes-1).each do |i|
         correct += @confusion_matrix[i][class_index] if i == class_index
         total += @confusion_matrix[i][class_index]
      end
      return 0 if total==0
      return correct/total.to_f
    end
    
    def recall(class_index=nil)
      return true_positive_rate(class_index)
    end
    
    def true_negative_rate(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| true_negative_rate(i) } ) if class_index==nil
      
      correct = 0
      total = 0
      (0..@num_classes-1).each do |i|
        if i != class_index
          (0..@num_classes-1).each do |j|    
            correct += @confusion_matrix[i][j] if j != class_index
            total +=  @confusion_matrix[i][j]
          end
        end
      end
      return 0 if total==0
      return correct/total.to_f
    end
    
    def num_true_negatives(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| num_true_negatives(i) } ) if class_index==nil
      
      correct = 0
      (0..@num_classes-1).each do |i|
        if i != class_index
          (0..@num_classes-1).each do |j|    
            correct += @confusion_matrix[i][j] if j != class_index
          end
        end
      end
      return correct
    end
    
    def true_positive_rate(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| true_positive_rate(i) } ) if class_index==nil
      
      correct = 0
      total = 0
      (0..@num_classes-1).each do |i|
        correct += @confusion_matrix[class_index][i] if i == class_index
        total += @confusion_matrix[class_index][i]
      end
      return 0 if total==0
      return correct/total.to_f
    end
    
    def num_true_positives(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| num_true_positives(i) } ) if class_index==nil
      
      correct = 0
      (0..@num_classes-1).each do |i|
        correct += @confusion_matrix[class_index][i] if i == class_index
      end
      return correct
    end
    
    def false_negative_rate(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| false_negative_rate(i) } ) if class_index==nil
      
      total = 0
      incorrect = 0
      (0..@num_classes-1).each do |i|
        if i == class_index
          (0..@num_classes-1).each do |j|
            incorrect += @confusion_matrix[i][j] if j != class_index
            total += @confusion_matrix[i][j]
          end
        end
      end
      return 0 if total == 0
      return incorrect / total.to_f
    end
    
    def num_false_negatives(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| num_false_negatives(i) } ) if class_index==nil
      
      incorrect = 0
      (0..@num_classes-1).each do |i|
        if i == class_index
          (0..@num_classes-1).each do |j|
            incorrect += @confusion_matrix[i][j] if j != class_index
          end
        end
      end
      return incorrect
    end

    def false_positive_rate(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| false_positive_rate(i) } ) if class_index==nil
      
      total = 0
      incorrect = 0
      (0..@num_classes-1).each do |i|
        if i != class_index
          (0..@num_classes-1).each do |j|
            incorrect += @confusion_matrix[i][j] if j == class_index
            total += @confusion_matrix[i][j]
          end
        end
      end
      return 0 if total == 0
      return incorrect / total.to_f
    end
    
    def num_false_positives(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| num_false_positives(i) } ) if class_index==nil
      
      incorrect = 0
      (0..@num_classes-1).each do |i|
        if i != class_index
          (0..@num_classes-1).each do |j|
            incorrect += @confusion_matrix[i][j] if j == class_index
          end
        end
      end
      return incorrect
    end
    
    # Note:
    # * (un-weighted) area under roc is computed with all __predicted__ isntances for a certain class
    # * weighted weights each auc with the number of __acutal__ instances
    # its like that, because its like that in weka   
    def weighted_area_under_roc
      w_auc = weighted_measure( :area_under_roc )
      w_auc.nan? ? 0 : w_auc
    end
    
    def weighted_f_measure
      return weighted_measure( :f_measure )
    end
    
    private
    # the <measure> is weighted with the number of instances for each actual class value 
    def weighted_measure( measure )
      
      sum_instances = 0
      num_instances_per_class = Array.new(@num_classes, 0)
      (0..@num_classes-1).each do |i|
        (0..@num_classes-1).each do |j|
          num_instances_per_class[i] += @confusion_matrix[i][j]
        end
        sum_instances += num_instances_per_class[i]
      end
      raise "sum instances ("+sum_instances.to_s+") != num predicted ("+@num_predicted.to_s+")" unless @num_predicted == sum_instances
      
      weighted = 0;
      (0..@num_classes-1).each do |i|
        weighted += self.send(measure,i) * num_instances_per_class[i]
      end
      return weighted / @num_predicted.to_f
    end
    
    # regression #######################################################################################
    
    public
    def root_mean_squared_error
      return 0 if (@num_with_actual_value - @num_unpredicted)==0
      mse = @sum_squared_error / (@num_with_actual_value - @num_unpredicted).to_f
      return 0 if mse.nan?
      Math.sqrt(mse)
    end
    
    def weighted_root_mean_squared_error
      return 0 unless confidence_values_available?      
      return 0 if (@num_with_actual_value - @num_unpredicted)==0
      Math.sqrt(@sum_weighted_squared_error / ((@num_with_actual_value - @num_unpredicted).to_f * @mean_confidence ))
    end    
    
    def mean_absolute_error
      return 0 if (@num_with_actual_value - @num_unpredicted)==0
      @sum_abs_error / (@num_with_actual_value - @num_unpredicted).to_f
    end
    
    def weighted_mean_absolute_error
      return 0 unless confidence_values_available?      
      return 0 if (@num_with_actual_value - @num_unpredicted)==0
      @sum_weighted_abs_error / ((@num_with_actual_value - @num_unpredicted).to_f * @mean_confidence )
    end
    
    def sum_squared_error
      return @sum_squared_error
    end
    
    def r_square
      #return sample_correlation_coefficient ** 2
      
      # see http://en.wikipedia.org/wiki/Coefficient_of_determination#Definitions
      # see http://web.maths.unsw.edu.au/~adelle/Garvan/Assays/GoodnessOfFit.html
      ss_tot = total_sum_of_squares
      return 0 if ss_tot==0
      r_2 = 1 - residual_sum_of_squares / ss_tot
      ( r_2.infinite? || r_2.nan? ) ? 0 : r_2
    end
    
    def weighted_r_square
      return 0 unless confidence_values_available?      
      ss_tot = weighted_total_sum_of_squares
      return 0 if ss_tot==0
      r_2 = 1 - weighted_residual_sum_of_squares / ss_tot
      ( r_2.infinite? || r_2.nan? ) ? 0 : r_2
    end
    
    def sample_correlation_coefficient
      # formula see http://en.wikipedia.org/wiki/Correlation_and_dependence#Pearson.27s_product-moment_coefficient
      scc = ( @num_predicted * @sum_multiply - @sum_actual * @sum_predicted ) /
             ( Math.sqrt( [0, @num_predicted * @sum_squares_actual - @sum_actual**2].max ) *
               Math.sqrt( [0, @num_predicted * @sum_squares_predicted - @sum_predicted**2].max ) )
      ( scc.infinite? || scc.nan? ) ? 0 : scc
    end
    
    def total_sum_of_squares
      #return @variance_actual * ( @num_predicted - 1 )
      sum = 0
      @predicted_values.size.times do |i|
        sum += (@actual_values[i]-@actual_mean)**2 if @actual_values[i]!=nil and @predicted_values[i]!=nil 
      end
      sum
    end
    
    def weighted_total_sum_of_squares
      return 0 unless confidence_values_available?
      sum = 0
      @predicted_values.size.times do |i|
        sum += ((@actual_values[i]-@actual_mean)**2)*@confidence_values[i] if @actual_values[i]!=nil and @predicted_values[i]!=nil 
      end
      sum
    end
    
    def residual_sum_of_squares
      sum_squared_error
    end
    
    def weighted_residual_sum_of_squares
      @sum_weighted_squared_error
    end
    
    def target_variance_predicted
      return @variance_predicted
    end

    def target_variance_actual
      return @variance_actual
    end

    # data for (roc-)plots ###################################################################################
    
    def get_prediction_values(class_value)
      
      #puts "get_roc_values for class_value: "+class_value.to_s
      raise "no confidence values" unless confidence_values_available?
      #raise "no class-value specified" if class_value==nil
      
      class_index = @accept_values.index(class_value) if class_value!=nil
      raise "class not found "+class_value.to_s if (class_value!=nil && class_index==nil)
      
      c = []; p = []; a = []
      (0..@predicted_values.size-1).each do |i|
        # NOTE: not predicted instances are ignored here
        if @predicted_values[i]!=nil and (class_index==nil || @predicted_values[i]==class_index)
          c << @confidence_values[i]
          p << @predicted_values[i]
          a << @actual_values[i]
        end
      end
      
      # DO NOT raise exception here, maybe different validations are concated
      #raise "no instance predicted as '"+class_value+"'" if p.size == 0
      
      h = {:predicted_values => p, :actual_values => a, :confidence_values => c}
      #puts h.inspect
      return h
    end
    
    ########################################################################################
    
    def num_instances
      return @predicted_values.size
    end
    
    def predicted_values
      @predicted_values
    end
  
    def predicted_value(instance_index)
      case @feature_type 
      when "classification"
        @predicted_values[instance_index]==nil ? nil : @accept_values[@predicted_values[instance_index]]
      when "regression"
        @predicted_values[instance_index]
      end
    end
    
    def actual_values
      @actual_values
    end
    
    def actual_value(instance_index)
      case @feature_type 
      when "classification"
        @actual_values[instance_index]==nil ? nil : @accept_values[@actual_values[instance_index]]
      when "regression"
        @actual_values[instance_index]
      end
    end
    
    def confidence_value(instance_index)
      return @confidence_values[instance_index]
    end      
    
    def classification_miss?(instance_index)
      raise "no classification" unless @feature_type=="classification"
      return false if predicted_value(instance_index)==nil or actual_value(instance_index)==nil
      return predicted_value(instance_index) != actual_value(instance_index)
    end
    
    def feature_type
      @feature_type
    end
    
    def confidence_values_available?
      @conf_provided
    end
    
    ###################################################################################################################
    
    #def compound(instance_index)
      #return "instance_index.to_s"
    #end
    
    private
    def prediction_feature_value_map(proc)
      res = {}
      (0..@num_classes-1).each do |i|
        res[@accept_values[i]] = proc.call(i)
      end
      return res
    end
    
  end
end