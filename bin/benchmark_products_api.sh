#!/usr/bin/env bash

set -eu

echo "[WARNING]: We assume that your PIM is already installed (meaning all your dependencies are installed) and your docker is configured, it will erase your test database"
echo "Do you wish to continue?"
select yn in "Yes" "No"; do
    case ${yn} in
        Yes ) break;;
        No ) echo "Ok, see you then"; exit;;
    esac
done

start=`date +%s`
SHELL_SCRIPT=`dirname $0`
DOCKER_BRIDGE_IP=`ip a s | grep "global docker" | cut -c10- | cut -d '/' -f1`
ABSOLUTE_SHELL_SCRIPT=`realpath ${SHELL_SCRIPT}`
WORKING_DIRECTORY="${ABSOLUTE_SHELL_SCRIPT}/../var/benchmarks"

PIM_PATH="${ABSOLUTE_SHELL_SCRIPT}/.."

DATA_GENERATOR_REPOSITORY='git@github.com:akeneo/akeneo-data-generator.git'
DATA_GENERATOR_PATH="${WORKING_DIRECTORY}/akeneo-data-generator"

BENCHMARK_REPOSITORY='git@github.com:akeneo/akeneo-benchmark.git'
BENCHMARK_PATH="${WORKING_DIRECTORY}/akeneo-benchmark"
BENCHMARK_API_PATH="${BENCHMARK_PATH}/api"

mkdir -p "${WORKING_DIRECTORY}/raw_results"

function generate_api_credentials
{
    cd ${PIM_PATH}
    CREDENTIALS=`docker-compose exec fpm bin/console pim:oauth-server:create-client --no-ansi -e prod generator`
    export API_CLIENT=`echo ${CREDENTIALS} | grep -o "client_id: \w*" | tr -d '\n' | cut -c12-`
    export API_SECRET=`echo ${CREDENTIALS} | grep -o "secret: \w*" | tr -d '\n' | cut -c9- `
    export API_URL="http://${DOCKER_BRIDGE_IP}:${PUBLIC_PIM_HTTP_PORT}"
    export API_USER="admin"
    export API_PASSWORD="admin"
}

function boot_benchmark
{
    cd ${BENCHMARK_API_PATH}
    docker-compose up -d --remove-orphans
    cd ${PIM_PATH}
}

function boot_data_generator
{
    cd ${DATA_GENERATOR_PATH}
    docker-compose up -d --remove-orphans
    cd ${PIM_PATH}
}

echo "======================================= Create the working directory ============================================"
mkdir -p ${WORKING_DIRECTORY}

echo "================================= Update akeneo-data-generator repository ======================================="
cd ${WORKING_DIRECTORY}
if [[ -d ${DATA_GENERATOR_PATH} ]]; then
    cd ${DATA_GENERATOR_PATH}
    git checkout -- .
    git checkout master
    git pull
    cd ${WORKING_DIRECTORY}
else
    git clone ${DATA_GENERATOR_REPOSITORY}
fi

echo "==================================== Update akeneo-benchmark repository ========================================="
if [[ -d ${BENCHMARK_PATH} ]]; then
    cd ${BENCHMARK_PATH}
    git checkout -- .
    git checkout master
    git pull
    cd ${WORKING_DIRECTORY}
else
    git clone ${BENCHMARK_REPOSITORY}
fi

echo "============================================== Boot the PIM ====================================================="
cd ${PIM_PATH}
docker-compose up -d --remove-orphans
PUBLIC_PIM_HTTP_PORT=`docker-compose port httpd 80 | cut -d ':' -f 2`

echo "================================== Start and install benchmark containers ======================================="
cd ${BENCHMARK_API_PATH}
docker-compose up -d --remove-orphans
docker-compose run php /usr/local/bin/composer install -n

echo "=============================== Start and install data-generator containers ====================================="
cd ${DATA_GENERATOR_PATH}
docker-compose up -d --remove-orphans
docker-compose run php /usr/local/bin/composer install -n

echo "=========================================== Install PIM minimal ================================================="
cd ${PIM_PATH}
rm -rf var/cache/*
cp app/config/parameters.yml app/config/parameters.yml.bak
rm app/config/parameters.yml
cp app/config/parameters_test.yml.dist app/config/parameters.yml
sed -i "s/database_host:.*localhost/database_host: mysql-behat/g" app/config/parameters.yml
sed -i "s/localhost: 9200/elasticsearch:9200/g" app/config/parameters.yml
sed -i "s/product_index_name:.*akeneo_pim_product/product_index_name: test_akeneo_pim_product/g" app/config/parameters.yml
sed -i "s/product_model_index_name:.*akeneo_pim_product_model/product_model_index_name: test_akeneo_pim_product_model/g" app/config/parameters.yml
sed -i "s/product_and_product_model_index_name:.*akeneo_pim_product_and_product_model/product_and_product_model_index_name: test_akeneo_pim_product_and_product_model/g" app/config/parameters.yml
docker-compose exec fpm bin/console cache:warmup -e prod
docker-compose exec fpm bin/console pim:installer:db -e prod
generate_api_credentials

cd ${DATA_GENERATOR_PATH}
echo "=============== Build the base reference_catalog (without families / attributes / products) ====================="
boot_data_generator

cd ${DATA_GENERATOR_PATH}
cp "${PIM_PATH}/var/benchmarks/product_api_catalog.yml" "${DATA_GENERATOR_PATH}/app/catalog/product_api_catalog.yml"
docker-compose run php bin/console akeneo:api:generate-catalog --with-products --check-minimal-install product_api_catalog.yml

echo "========================= Start bench products with 120 attributes ================================"
cd ${PIM_PATH}
PRODUCT_SIZE=$(docker-compose exec mysql-behat mysql -uakeneo_pim -pakeneo_pim akeneo_pim -N -s -e "select AVG(JSON_LENGTH(JSON_EXTRACT(raw_values, '$.*.*.*'))) avg_product_values FROM pim_catalog_product;" | tail -n -1 | grep -Eo '[0-9]+([.][0-9]+)?')

echo ">>>>>> Start Benchmark"
boot_benchmark
cd ${BENCHMARK_API_PATH}
docker-compose run php bin/console akeneo:api:launch-benchmarks -i 10 -b "get_many_products" -vv > "${WORKING_DIRECTORY}/raw_results/get_results.txt"
docker-compose run php bin/console akeneo:api:launch-benchmarks -i 10 -b "create_many_products" -vv > "${WORKING_DIRECTORY}/raw_results/create_results.txt"
docker-compose run php bin/console akeneo:api:launch-benchmarks -i 10 -b "update_many_products" -vv > "${WORKING_DIRECTORY}/raw_results/update_results.txt"

cd "${WORKING_DIRECTORY}/raw_results"
GET=$(cat "get_results.txt" | grep "Mean speed" | cut -c46- | grep -Eo '[0-9]+([.][0-9]+)?')
CREATE=$(cat "create_results.txt" | grep "Mean speed" | cut -c46- | grep -Eo '[0-9]+([.][0-9]+)?')
UPDATE=$(cat "update_results.txt" | grep "Mean speed" | cut -c46- | grep -Eo '[0-9]+([.][0-9]+)?')

echo "Currently with 1000 products with ${PRODUCT_SIZE} values in average, the api speeds are:"
echo "- GET: ${GET} products/second"
echo "- CREATE: ${CREATE} products/second"
echo "- UPDATE: ${UPDATE} products/second"
echo ""
echo "You can see the detailed results under the folder ${WORKING_DIRECTORY}/raw_results"
echo ""

cd ${PIM_PATH}
rm app/config/parameters.yml
mv app/config/parameters.yml.bak app/config/parameters.yml

end=`date +%s`
runtime=$((end-start))
echo "The bench is finished, it took ${runtime} seconds to run"
