
require "lib/prediction_data.rb"

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
    
    def initialize( data )
      raise unless data.is_a?(Hash)
                    
      @feature_type = data[:feature_type]
      @accept_values = data[:accept_values]
      @num_classes = 1
      
      #puts "predicted:  "+predicted_values.inspect
      #puts "actual:     "+actual_values.inspect
      #puts "confidence: "+confidence_values.inspect
      
      raise "unknown feature_type: '"+@feature_type.to_s+"'" unless 
        @feature_type=="classification" || @feature_type=="regression"
      raise "no predictions" if data[:predicted_values].size == 0
      num_info = "predicted:"+data[:predicted_values].size.to_s+
        " confidence:"+data[:confidence_values].size.to_s+" actual:"+data[:actual_values].size.to_s
      raise "illegal num actual values "+num_info if  data[:actual_values].size != data[:predicted_values].size
      raise "illegal num confidence values "+num_info if  data[:confidence_values].size != data[:predicted_values].size
      
      case @feature_type
      when "classification"
        raise "accept_values missing while performing classification" unless @accept_values
        @num_classes = @accept_values.size
        raise "num classes < 2" if @num_classes<2
      when "regression"
        raise "accept_values != nil while performing regression" if @accept_values
      end
      
      @predicted_values = []
      @actual_values = []
      @confidence_values = []
      init_stats()
      (0..data[:predicted_values].size-1).each do |i|
        update_stats( data[:predicted_values][i], data[:actual_values][i], data[:confidence_values][i] )
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
        
        @sum_confidence = 0
        @weighted_sum_actual = 0
        @weighted_sum_predicted = 0
        @weighted_sum_multiply = 0
        @weighted_sum_squares_actual = 0
        @weighted_sum_squares_predicted = 0
        
        @sum_weighted_abs_error = 0
        @sum_weighted_squared_error = 0
      end
    end
    
    def update_stats( predicted_value, actual_value, confidence_value )
      
      raise "illegal confidence value: '"+confidence_value.to_s+"'" unless 
        confidence_value==nil or (confidence_value.is_a?(Numeric) and confidence_value>=0 and confidence_value<=1)
      case @feature_type
      when "classification"
        { "predicted"=>predicted_value, "actual"=>actual_value }.each do |s,v|
          raise "illegal "+s+" classification-value ("+v.to_s+"),"+
            "has to be either nil or index of predicted-values" if v!=nil and (!v.is_a?(Numeric) or v<0 or v>@num_classes)
        end
      when "regression"
        { "predicted"=>predicted_value, "actual"=>actual_value }.each do |s,v|
          raise "illegal "+s+" regression-value ("+v.to_s+"),"+
            " has to be either nil or number (not NaN, not Infinite)" unless v==nil or (v.is_a?(Numeric) and !v.nan? and v.finite?)
        end
      end
      
      @predicted_values << predicted_value
      @actual_values << actual_value
      @confidence_values << confidence_value
      
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
            
            if @conf_provided
              w_a = actual_value * confidence_value
              w_p = predicted_value * confidence_value
              @weighted_sum_actual += w_a
              @weighted_sum_predicted += w_p
              @weighted_sum_multiply += (w_a*w_p) if @conf_provided
              @weighted_sum_squares_actual += w_a**2 if @conf_provided
              @weighted_sum_squares_predicted += w_p**2 if @conf_provided
            end
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
    
    # returns acutal values for a certain prediction
    def confusion_matrix_row(predicted_class_index)
      r = []
      (0..@num_classes-1).each do |actual|
        r << @confusion_matrix[actual][predicted_class_index]
      end
      return r
    end
    
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
        if @predicted_values[i]!=nil
          c = @confidence_values[i] * (@predicted_values[i]==class_index ? 1 : -1)
          if @actual_values[i]==class_index
            tp_conf << c
          else
            fp_conf << c
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
      return positive_predictive_value(class_index)
    end
    
    def positive_predictive_value(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| positive_predictive_value(i) } ) if class_index==nil
      
      correct = 0 # all instances with prediction class_index that are correctly classified 
      total = 0 # all instances with prediciton class_index
      (0..@num_classes-1).each do |i|
         correct += @confusion_matrix[i][class_index] if i == class_index
         total += @confusion_matrix[i][class_index]
      end
      return 0 if total==0
      return correct/total.to_f
    end
    
    def negative_predictive_value(class_index=nil)
      return prediction_feature_value_map( lambda{ |i| negative_predictive_value(i) } ) if class_index==nil
      
      correct = 0 # all instances with prediction class_index that are correctly classified 
      total = 0 # all instances with prediciton class_index
      (0..@num_classes-1).each do |i|
        if i != class_index
          (0..@num_classes-1).each do |j|
            correct += @confusion_matrix[j][i] if j != class_index
            total += @confusion_matrix[j][i]
          end
        end
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
    
    def average_area_under_roc
      w_auc = average_measure( :area_under_roc )
      w_auc.nan? ? 0 : w_auc
    end
    
    def average_f_measure
      return average_measure( :f_measure )
    end
    
    private
    # the <measure> is averaged over the number of instances for each actual class value 
    def average_measure( measure )
      
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
    
    def r_square #_old
      #return sample_correlation_coefficient ** 2
      
      # see http://en.wikipedia.org/wiki/Coefficient_of_determination#Definitions
      # see http://web.maths.unsw.edu.au/~adelle/Garvan/Assays/GoodnessOfFit.html
      ss_tot = total_sum_of_squares
      return 0 if ss_tot==0
      r_2 = 1 - residual_sum_of_squares / ss_tot
      ( r_2.infinite? || r_2.nan? ) ? 0 : r_2
    end
    
    def weighted_r_square #_old
      return 0 unless confidence_values_available?      
      ss_tot = weighted_total_sum_of_squares
      return 0 if ss_tot==0
      r_2 = 1 - weighted_residual_sum_of_squares / ss_tot
      ( r_2.infinite? || r_2.nan? ) ? 0 : r_2
    end
    
    #def r_square
    #  # as implemted in R
    #  return sample_correlation_coefficient ** 2
    #end
    
    #def weighted_r_square
    #  # as implemted in R
    #  return weighted_sample_correlation_coefficient ** 2
    #end
    
    def concordance_correlation_coefficient
      begin
        numerator = 0
        @predicted_values.size.times do |i|
          numerator += (@actual_values[i]-@actual_mean) * (@predicted_values[i]-@prediction_mean) if  
            @actual_values[i]!=nil and @predicted_values[i]!=nil 
        end
        numerator *= 2
        denominator = total_sum_of_squares 
        denominator += prediction_total_sum_of_squares
        denominator += @num_predicted * (@actual_mean - @prediction_mean)**2
        ccc = numerator / denominator
        ( ccc.infinite? || ccc.nan? ) ? 0 : ccc
      rescue; 0; end
    end
    
    def prediction_total_sum_of_squares
      #return @variance_actual * ( @num_predicted - 1 )
      sum = 0
      @predicted_values.size.times do |i|
        sum += (@predicted_values[i]-@prediction_mean)**2 if @actual_values[i]!=nil and @predicted_values[i]!=nil 
      end
      sum
    end
    
    def sample_correlation_coefficient
      begin
        # formula see http://en.wikipedia.org/wiki/Correlation_and_dependence#Pearson.27s_product-moment_coefficient
        scc = ( @num_predicted * @sum_multiply - @sum_actual * @sum_predicted ) /
          ( Math.sqrt( @num_predicted * @sum_squares_actual - @sum_actual**2 ) *
            Math.sqrt( @num_predicted * @sum_squares_predicted - @sum_predicted**2 ) )
        ( scc.infinite? || scc.nan? ) ? 0 : scc
      rescue; 0; end
    end
    
    def weighted_sample_correlation_coefficient
      begin
        # formula see http://en.wikipedia.org/wiki/Correlation_and_dependence#Pearson.27s_product-moment_coefficient
        scc = ( @num_predicted * @weighted_sum_multiply - @weighted_sum_actual * @weighted_sum_predicted ) /
          ( Math.sqrt( @num_predicted * @weighted_sum_squares_actual - @weighted_sum_actual**2 ) *
            Math.sqrt( @num_predicted * @weighted_sum_squares_predicted - @weighted_sum_predicted**2 ) )
        ( scc.infinite? || scc.nan? ) ? 0 : scc
      rescue; 0; end
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
    
     def get_roc_prediction_values(class_value)
      
      #puts "get_roc_values for class_value: "+class_value.to_s
      raise "no confidence values" unless confidence_values_available?
      raise "no class-value specified" if class_value==nil
      
      class_index = @accept_values.index(class_value) if class_value!=nil
      raise "class not found "+class_value.to_s if (class_value!=nil && class_index==nil)
      
      c = []; tp = []
      (0..@predicted_values.size-1).each do |i|
        if @predicted_values[i]!=nil
          c << @confidence_values[i] * (@predicted_values[i]==class_index ? 1 : -1)
          if (@actual_values[i]==class_index)
            tp << 1
          else
            tp << 0
          end
        end
      end
      
      # DO NOT raise exception here, maybe different validations are concated
      #raise "no instance predicted as '"+class_value+"'" if p.size == 0
      
      h = {:true_positives => tp, :confidence_values => c}
      #puts h.inspect
      return h
    end
    
    def get_prediction_values(performance_attr, performance_accept_value)
      
      #puts "get_roc_values for class_value: "+class_value.to_s
      raise "no confidence values" unless confidence_values_available?
      #raise "no class-value specified" if class_value==nil
      
      actual_accept_value = nil
      predicted_accept_value = nil
      if performance_attr==:true_positive_rate
        actual_accept_value = performance_accept_value
      elsif performance_attr==:positive_predictive_value
        predicted_accept_value = performance_accept_value
      end
      actual_class_index = @accept_values.index(actual_accept_value) if actual_accept_value!=nil
      raise "class not found '"+actual_accept_value.to_s+"' in "+@accept_values.inspect if (actual_accept_value!=nil && actual_class_index==nil)
      predicted_class_index = @accept_values.index(predicted_accept_value) if predicted_accept_value!=nil
      raise "class not found '"+predicted_accept_value.to_s+"' in "+@accept_values.inspect if (predicted_accept_value!=nil && predicted_class_index==nil)
      
      c = []; p = []; a = []
      (0..@predicted_values.size-1).each do |i|
        # NOTE: not predicted instances are ignored here
        if @predicted_values[i]!=nil and 
            (predicted_class_index==nil || @predicted_values[i]==predicted_class_index) and
            (actual_class_index==nil || @actual_values[i]==actual_class_index)
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
    
    def min_confidence
      @confidence_values[-1]
    end
    
    ###################################################################################################################
    
    #def compound(instance_index)
      #return "instance_index.to_s"
    #end
    
    private
    def self.test_update
      p=[0.4,0.2,0.3,0.5,0.8]
      a=[0.45,0.21,0.25,0.55,0.75]
      c = Array.new(p.size)
      pred = Predictions.new(p,a,c,"regression")
      puts pred.r_square
      
      pred = nil
      p.size.times do |i|
        if pred==nil
          pred = Predictions.new([p[0]],[a[0]],[c[0]],"regression")
        else
          pred.update_stats(p[i],a[i],c[i])
        end
        puts pred.r_square
      end
    end
    
    def self.test_r_square
      require "rubygems"
      require "opentox-ruby"
      
      max_deviation = rand * 0.9
      avg_deviation = max_deviation * 0.5
      
      p = []
      a = []
      c = []
      (100 + rand(1000)).times do |i|
        r = rand
        deviation = rand * max_deviation
        a << r
        p << r + ((rand<0.5 ? -1 : 1) * deviation)
        #c << 0.5
        if (deviation > avg_deviation)
          c << 0.4
        else
          c << 0.6
        end
        #puts a[-1].to_s+" "+p[-1].to_s
      end
      puts "num values "+p.size.to_s
      
      #a = [1.0,2.0, 3.0,4.0, 5.0]
      #p = [1.5,2.25,3.0,3.75,4.5]
      
      #a = [1.0,2.0,3.0,4.0,5.0]
      #p = [1.5,2.5,3.5,4.5,5.5]

      #p = a.collect{|v| v-0.5} 
      #p = a.collect{|v| v+0.5}
      
      #p = [2.0,2.5,3.0,3.5,4.0]
      
      c = Array.new(p.size,nil)
      
      data = { :predicted_values => p, :actual_values => a, :confidence_values => c,
        :feature_type => "regression", :accept_values => nil }
            
      pred = Predictions.new(data)
      puts "internal"
      #puts "r-square old        "+pred.r_square_old.to_s
      puts "cor                 "+pred.sample_correlation_coefficient.to_s
      #puts "weighted cor        "+pred.weighted_sample_correlation_coefficient.to_s
      puts "r-square            "+pred.r_square.to_s
      puts "ccc                 "+pred.concordance_correlation_coefficient.to_s
      
      puts "R"
      rutil = OpenTox::RUtil.new
      
      rutil.r.assign "v1",a
      rutil.r.assign "v2",p
      puts "r cor               "+rutil.r.pull("cor(v1,v2)").to_s
      rutil.r.eval "fit <- lm(v1 ~ v2)"
      rutil.r.eval "sum <- summary(fit)"
      puts "r r-square          "+rutil.r.pull("sum$r.squared").to_s
      puts "r adjusted-r-square "+rutil.r.pull("sum$adj.r.squared").to_s
      #rutil.r.eval "save.image(\"/tmp/image.R\")"
      #rutil.r.eval "require(epiR)"
      #rutil.r.eval "tmp.ccc <- epi.ccc(v1,v2)"
      #puts "r ccc               "+rutil.r.pull("tmp.ccc$rho.c$est").to_s
      rutil.quit_r
    end

    def prediction_feature_value_map(proc)
      res = {}
      (0..@num_classes-1).each do |i|
        res[@accept_values[i]] = proc.call(i)
      end
      return res
    end
    
  end
end

#class Float
#  def to_s
#    "%.5f" % self
#  end
#end
##Lib::Predictions.test_update
#Lib::Predictions.test_r_square
