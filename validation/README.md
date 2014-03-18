Directory: validation - OpenTox Validation
=======================================

author: Martin Guetlein, date: 2014-03-18

General
-------

* a *validation* object resembles a test-set validation, e.g. compounds in the test-set are predicted, prediciton quality is measured
* different types of *validation*s:
 * **test-set-validation** input: model and test-set, no algorithm, no training-set
 * **training-test-validation** input: algorithm, test-set, training-set
 * **training-test-split** input: algorithm, dataset, split-ratio
 * **bootstrapping** input: algorithm, dataset
* k-fold *crossvalidation* creates k *validation* objects and an additional *validation* object that stores the aggregated statistics

Code
----

* **validation_application.rb** REST call handling
* **validation_format.rb** to_rdf and to_yaml stuff
* **validation_service.rb** does the actual validation work (e.g. model building)
* **validation_test.rb** test-routines for debugging

