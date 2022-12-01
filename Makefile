PROJECT_ID ?= <CHANGE>
REGION ?= <CHANGE>
ARTIFACT_REGISTRY ?= <CHANGE>
PROJECT_NUMBER ?= $$(gcloud projects list --filter=${PROJECT_ID} --format="value(PROJECT_NUMBER)")
CODE_BUCKET ?= serverless-spark-code-repo-${PROJECT_NUMBER}
TEMP_BUCKET ?= serverless-spark-staging-${PROJECT_NUMBER}
DATA_BUCKET ?= serverless-spark-data-${PROJECT_NUMBER}
APP_NAME ?= $$(cat pyproject.toml| grep name | cut -d" " -f3 | sed  's/"//g')
VERSION_NO ?= $$(poetry version --short)
SRC_WITH_DEPS ?= src_with_deps

.PHONY: $(shell sed -n -e '/^$$/ { n ; /^[^ .\#][^ ]*:/ { s/:.*$$// ; p ; } ; }' $(MAKEFILE_LIST))

.DEFAULT_GOAL := help

help: ## This is help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Setup Buckets and Dataset for Demo
	@echo "Project=${PROJECT_ID}--${PROJECT_NUMBER}--${CODE_BUCKET}--${TEMP_BUCKET}"
	@gsutil mb -c standard -l ${REGION} -p ${PROJECT_ID} gs://${CODE_BUCKET}
	@gsutil mb -c standard -l ${REGION} -p ${PROJECT_ID} gs://${TEMP_BUCKET}
	@gsutil mb -c standard -l ${REGION} -p ${PROJECT_ID} gs://${DATA_BUCKET}
	@gsutil cp ./stocks.csv gs://${DATA_BUCKET}
	@echo "The Following Buckets created - ${CODE_BUCKET}, ${TEMP_BUCKET}, ${DATA_BUCKET}"

clean: ## CleanUp Prior to Build
	@rm -Rf ./dist
	@rm -Rf ./${SRC_WITH_DEPS}
	@rm -f requirements.txt

build: clean ## Build Python Package with Dependencies
	@echo "Packaging Code and Dependencies for ${APP_NAME}-${VERSION_NO}"
	@mkdir -p ./dist
	@poetry update
	@poetry export -f requirements.txt --without-hashes -o requirements.txt
	@poetry run pip install . -r requirements.txt -t ${SRC_WITH_DEPS}
	@cd ./${SRC_WITH_DEPS}
	@find . -name "*.pyc" -delete
	@cd ./${SRC_WITH_DEPS} && zip -x "*.git*" -x "*.DS_Store" -x "*.pyc" -x "*/*__pycache__*/" -x ".idea*" -r ../dist/${SRC_WITH_DEPS}.zip .
	@rm -Rf ./${SRC_WITH_DEPS}
	@rm -f requirements.txt
	@cp ./src/main.py ./dist
	@mv ./dist/${SRC_WITH_DEPS}.zip ./dist/${APP_NAME}_${VERSION_NO}.zip
	@gsutil cp -r ./dist gs://${CODE_BUCKET}

image: ## Build docker image and push them to gcr.io
	@echo "Building docker image. PROJECT_ID=${PROJECT_ID}, ARTIFACT_REGISTRY=${ARTIFACT_REGISTRY}"
	@docker build -t spark-dataproc-serverless-example .
	@docker tag spark-dataproc-serverless-example ${ARTIFACT_REGISTRY}/${PROJECT_ID}/registry/spark-dataproc-serverless-example
	@docker push ${ARTIFACT_REGISTRY}/${PROJECT_ID}/registry/spark-dataproc-serverless-example

run: ## Run the dataproc serverless job
	gcloud beta dataproc batches submit --project ${PROJECT_ID} --region ${REGION} pyspark \
	gs://${CODE_BUCKET}/dist/main.py --py-files=gs://${CODE_BUCKET}/dist/${APP_NAME}_${VERSION_NO}.zip \
	--subnet default --properties spark.executor.instances=2,spark.driver.cores=4,spark.executor.cores=4,spark.app.name=spark_serverless_repo_exemplar \
	-- --project=${PROJECT_ID} --file-uri=gs://${DATA_BUCKET}/stocks.csv --temp-bq-bucket=${TEMP_BUCKET}

start: ## Run the dataproc serverless job with custom container
	@echo "Code Bucket=${CODE_BUCKET}, Region=${REGION}, Project ID=${PROJECT_ID}, Data bucket=${DATA_BUCKET}, Temp bucket=${TEMP_BUCKET}"
	gcloud beta dataproc batches submit --project ${PROJECT_ID} --region ${REGION} pyspark \
	gs://${CODE_BUCKET}/dist/main.py  \
	--container-image ${ARTIFACT_REGISTRY}/${PROJECT_ID}/registry/spark-dataproc-serverless-example:latest \
	--subnet default --properties spark.executor.instances=2,spark.driver.cores=4,spark.executor.cores=4,spark.app.name=spark_serverless_repo_exemplar \
	-- --project=${PROJECT_ID} --file-uri=gs://${DATA_BUCKET}/stocks.csv --temp-bq-bucket=${TEMP_BUCKET}