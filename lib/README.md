Directory: lib - OpenTox Validation
=======================================

author: Martin Guetlein, date: 2014-03-18

Code
----

* **dataset_cache.rb** stores datasets in memmory
* **format_util.rb** util class for formatting to rdf / yaml
* **merge.rb** general merge class, to merge e.g. numeric arrays, computes mean and variance
* **ohm_util.rb** utils for redis (ohm is gem for redis)
* **predictions.rb** prediction statistics for classification and regression
* **ot_predictions.rb** extends predictions.rb, mainly by storing predicted compounds
* **prediction_data.rb** compounds and input data for predictions.rb, can be filtered
* **test_util.rb** util for debugging and testing
* **validation_db.rb** validation and crossvalidation redis-objects, validation-statistic fields
