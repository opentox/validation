#require "rubygems"
#require "rinruby"

module Reports
 
  class ReportStatisticalTest
    
    # __grouped_validations__ : array of validation arrays
    def self.test_matrix( validations, group_attribute, test_attribute, class_value, test_method="ttest", significance_level=0.95 )
      
      raise "statistical-test: '"+test_method+"' does not exist" unless ReportStatisticalTest.respond_to?(test_method)
      grouped_validations = Reports::Util.group(validations, [group_attribute])
      LOGGER.debug "perfom test '"+test_method.to_s+"' for '"+test_attribute.to_s+"' for #"+grouped_validations.size.to_s+" "+group_attribute.to_s
      
      titles = []
      matrix = []
      grouped_validations.size.times do |i|
        
        validations1 = grouped_validations[i]
        title1 = validations1[0].send(group_attribute)
        titles << title1
        matrix[i] = [] unless matrix[i]
        
        grouped_validations.size.times do |j|
          if (i == j)
            matrix[i][j] = nil
          else
            validations2 = grouped_validations[j]
            title2 = validations2[0].send(group_attribute)
            matrix[i][j] = ReportStatisticalTest.send(test_method,validations1,validations2,
              test_attribute, class_value, significance_level)
          end
        end
      end
      {:titles => titles, :matrix => matrix, :num_results => grouped_validations[0].size}
    end
    
    def self.ttest( validations1, validations2, attribute, class_value, significance_level=0.95 )
      
      array1 = validations1.collect{ |v| (v.send(attribute).is_a?(Hash) ? v.send(attribute)[class_value].to_f : v.send(attribute).to_f) }
      array2 = validations2.collect{ |v| (v.send(attribute).is_a?(Hash) ? v.send(attribute)[class_value].to_f : v.send(attribute).to_f) }
      LOGGER.debug "paired-t-testing "+attribute.to_s+" "+array1.inspect+" vs "+array2.inspect
      if array1.size>1 && array2.size>1
        Reports::r_util.paired_ttest(array1, array2, significance_level)
      elsif array1.size==1 && array2.size>1
         -1 * Reports::r_util.ttest(array2, array1[0], significance_level)
      elsif array1.size>1 && array2.size==1
         Reports::r_util.ttest(array1, array2[0], significance_level)
      else
        raise "illegal input for ttest"
      end
    end
    
  end

end



