TODOs for validation service
============================

author: Martin Guetlein, date: 2014-03-18

Refactoring
-----------

* remove redis, replace with 4store
* remove gnuplot, replace with R
* to_json support

Pitfalls
--------

* for better performance datasets are cached in memory (see lib/dataset_cache.rb), this might cause memmory issues when working with large datasets
* validation objects does store predictions in dataset (for better performance, to not read all datasets and models again), this can cause redis to get pretty large
* redis does load everything into main memmory, can cause memmory problems on the long run