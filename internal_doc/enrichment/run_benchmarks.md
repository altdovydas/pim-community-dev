# Benchmarks

It is really important to take care of the non regression of performances.

That's why we made a script available here `bin/benchmark_product_api.sh`

Caution: the script works only through docker and relies on our current stack.
It uses the `data-generator` and the `benchmark` repository.

This script uses the reference catalog in order to know what are the API performances.
The catalog used is available here `var/benchmarks/product_api_catalog.yml`

## How to use it ? : 15h34

You need to have installed your PIM with docker prior to launch the benchmarks.

`$ bin/benchmark_product_api.sh`

It gives as a result the average speed on GET, CREATE, and UPDATE products through the API.

That's why you should launch the benchmark before and after any changes you make on the PIM.
