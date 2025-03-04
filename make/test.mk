###########################################################
#
# End-to-end Tests
#
###########################################################

QUAY_NAMESPACE ?= codeready-toolchain-test
DATE_SUFFIX := $(shell date +'%d%H%M%S')
HOST_NS ?= toolchain-host-${DATE_SUFFIX}
MEMBER_NS ?= toolchain-member-${DATE_SUFFIX}

SECOND_MEMBER_MODE = true

ifeq ($(SECOND_MEMBER_MODE),true)
MEMBER_NS_2 ?= toolchain-member2-${DATE_SUFFIX}
endif

REGISTRATION_SERVICE_NS := $(HOST_NS)

ENVIRONMENT := e2e-tests
IMAGE_NAMES_DIR := /tmp/crt-e2e-image-names

DEPLOY_LATEST := false

ifneq ($(CLONEREFS_OPTIONS),)
PUBLISH_OPERATOR := false
else
PUBLISH_OPERATOR := true
endif

SETUP_E2E_SERVICE_ACCOUNTS ?= true

.PHONY: test-e2e
## Run the e2e tests
test-e2e: INSTALL_OPERATOR=true
test-e2e: prepare-e2e verify-migration-and-deploy-e2e e2e-run
	@echo "The tests successfully finished"
	@echo "To clean the cluster run 'make clean-e2e-resources'"

.PHONY: test-e2e-without-migration
## Run the e2e tests without migration tests
test-e2e-without-migration: prepare-e2e deploy-e2e e2e-run
	@echo "To clean the cluster run 'make clean-e2e-resources'"

.PHONY: verify-migration-and-deploy-e2e
verify-migration-and-deploy-e2e: prepare-projects e2e-deploy-latest e2e-service-account setup-toolchainclusters e2e-migration-setup get-publish-and-install-operators e2e-migration-verify

.PHONY: e2e-migration-setup
e2e-migration-setup:
	@echo "Setting up the environment before testing the operator migration..."
	$(MAKE) execute-tests MEMBER_NS=${MEMBER_NS} MEMBER_NS_2=${MEMBER_NS_2} HOST_NS=${HOST_NS} REGISTRATION_SERVICE_NS=${REGISTRATION_SERVICE_NS} TESTS_TO_EXECUTE="./test/migration/setup"
	@echo "Environment successfully setup."

.PHONY: e2e-migration-verify
e2e-migration-verify:
	@echo "Updating operators and verifying resources..."
	$(MAKE) execute-tests MEMBER_NS=${MEMBER_NS} MEMBER_NS_2=${MEMBER_NS_2} HOST_NS=${HOST_NS} REGISTRATION_SERVICE_NS=${REGISTRATION_SERVICE_NS} TESTS_TO_EXECUTE="./test/migration/verify"
	@echo "Migration tests successfully finished"

.PHONY: e2e-deploy-latest
e2e-deploy-latest:
	$(MAKE) get-publish-and-install-operators MEMBER_NS=${MEMBER_NS} MEMBER_NS_2=${MEMBER_NS_2} HOST_NS=${HOST_NS} REGISTRATION_SERVICE_NS=${REGISTRATION_SERVICE_NS} ENVIRONMENT=${ENVIRONMENT} INSTALL_OPERATOR=${INSTALL_OPERATOR} DEPLOY_LATEST=true

.PHONY: prepare-e2e
prepare-e2e: build clean-e2e-files create-has-application-crd

.PHONY: deploy-e2e
deploy-e2e: INSTALL_OPERATOR=true
deploy-e2e: prepare-projects get-publish-and-install-operators e2e-service-account setup-toolchainclusters
	@echo "Operators are successfuly deployed using the ${ENVIRONMENT} environment."
	@echo ""

label-olm-ns:
# adds a label on the oc label ns/openshift-operator-lifecycle-manager name=openshift-operator-lifecycle-manager
# so that deployment also works when network policies were configured with `sandbox-cli`
	@-oc label --overwrite=true ns/openshift-operator-lifecycle-manager name=openshift-operator-lifecycle-manager
	
.PHONY: test-e2e-local
## Run the e2e tests with the local 'host', 'member', and 'registration-service' repositories
test-e2e-local:
	$(MAKE) test-e2e HOST_REPO_PATH=${PWD}/../host-operator MEMBER_REPO_PATH=${PWD}/../member-operator REG_REPO_PATH=${PWD}/../registration-service

.PHONY: deploy-e2e-local
## Deploy the e2e environment with the local 'host', 'member', and 'registration-service' repositories
deploy-e2e-local:
	$(MAKE) deploy-e2e HOST_REPO_PATH=${PWD}/../host-operator MEMBER_REPO_PATH=${PWD}/../member-operator REG_REPO_PATH=${PWD}/../registration-service

.PHONY: test-e2e-member-local
## Run the e2e tests with the local 'member' repository only
test-e2e-member-local:
	$(MAKE) test-e2e MEMBER_REPO_PATH=${PWD}/../member-operator

.PHONY: test-e2e-host-local
## Run the e2e tests with the local 'host' repository only
test-e2e-host-local:
	$(MAKE) test-e2e HOST_REPO_PATH=${PWD}/../host-operator

.PHONY: test-e2e-registration-local
## Run the e2e tests with the local 'registration' repository only
test-e2e-registration-local:
	$(MAKE) test-e2e REG_REPO_PATH=${PWD}/../registration-service

.PHONY: e2e-run
e2e-run:
	@echo "Running e2e tests..."
	$(MAKE) execute-tests MEMBER_NS=${MEMBER_NS} MEMBER_NS_2=${MEMBER_NS_2} HOST_NS=${HOST_NS} REGISTRATION_SERVICE_NS=${REGISTRATION_SERVICE_NS} TESTS_TO_EXECUTE="./test/e2e ./test/metrics"
	@echo "The e2e tests successfully finished"

.PHONY: execute-tests
execute-tests:
	@echo "Starting test $(shell date)"
	MEMBER_NS=${MEMBER_NS} MEMBER_NS_2=${MEMBER_NS_2} HOST_NS=${HOST_NS} REGISTRATION_SERVICE_NS=${REGISTRATION_SERVICE_NS} go test ${TESTS_TO_EXECUTE} -p 1 -v -timeout=90m -failfast || \
	($(MAKE) print-logs HOST_NS=${HOST_NS} MEMBER_NS=${MEMBER_NS} MEMBER_NS_2=${MEMBER_NS_2} REGISTRATION_SERVICE_NS=${REGISTRATION_SERVICE_NS} && exit 1)

.PHONY: print-logs
print-logs:
	@echo "Time: $(shell date)"
ifneq ($(OPENSHIFT_BUILD_NAMESPACE),)
	$(MAKE) print-operator-logs DEPLOYMENT_NAME=host-operator-controller-manager NAMESPACE=${HOST_NS} ADDITIONAL_PARAMS="-c manager"
	$(MAKE) print-operator-logs DEPLOYMENT_NAME=member-operator-controller-manager NAMESPACE=${MEMBER_NS} ADDITIONAL_PARAMS="-c manager"
	$(MAKE) print-operator-logs DEPLOYMENT_NAME=member-operator-webhook NAMESPACE=${MEMBER_NS}
	if [[ ${SECOND_MEMBER_MODE} == true ]]; then $(MAKE) print-operator-logs DEPLOYMENT_NAME=member-operator-controller-manager NAMESPACE=${MEMBER_NS_2} ADDITIONAL_PARAMS="-c manager"; fi
	$(MAKE) print-operator-logs DEPLOYMENT_NAME=registration-service NAMESPACE=${REGISTRATION_SERVICE_NS}
else
	$(MAKE) print-local-debug-info  HOST_NS=${HOST_NS} MEMBER_NS=${MEMBER_NS} MEMBER_NS_2=${MEMBER_NS_2} REGISTRATION_SERVICE_NS=${REGISTRATION_SERVICE_NS}
endif

.PHONY: deploy-e2e-local-and-print-local-debug
deploy-e2e-local-and-print-local-debug: deploy-e2e-local print-local-debug-info

.PHONY: deploy-e2e-and-print-local-debug
deploy-e2e-and-print-local-debug: deploy-e2e print-local-debug-info

.PHONY: print-local-debug-info
print-local-debug-info:
	@echo "You can print logs using the commands:"
	@echo "oc logs deployment.apps/host-operator-controller-manager -c manager --namespace ${HOST_NS}"
	@echo "oc logs deployment.apps/member-operator-controller-manager -c manager --namespace ${MEMBER_NS}"
	@if [[ ${SECOND_MEMBER_MODE} == true ]]; then echo "oc logs deployment.apps/member-operator-controller-manager -c manager --namespace ${MEMBER_NS_2}"; fi
	@echo "oc logs deployment.apps/member-operator-webhook --namespace ${MEMBER_NS}"
	@echo "oc logs deployment.apps/registration-service --namespace ${REGISTRATION_SERVICE_NS}"
	@echo ""
	@echo "Add the following lines at the very beginning of the test/suite that you want to run/debug from your IDE:"
	@echo 'os.Setenv("MEMBER_NS","${MEMBER_NS}")'
	@echo 'os.Setenv("MEMBER_NS_2","${MEMBER_NS_2}")'
	@echo 'os.Setenv("HOST_NS","${HOST_NS}")'
	@echo 'os.Setenv("REGISTRATION_SERVICE_NS","${REGISTRATION_SERVICE_NS}")'


.PHONY: print-operator-logs
print-operator-logs:
	@echo "==============================================================================================================="
	@echo "========================== ${DEPLOYMENT_NAME} deployment YAML- Namespace: ${NAMESPACE} ============================="
	@echo "==============================================================================================================="
	-oc get deployment.apps/${DEPLOYMENT_NAME} --namespace ${NAMESPACE} -o yaml
	@echo "==============================================================================================================="
	@echo "========================== ${DEPLOYMENT_NAME} pod YAML- Namespace: ${NAMESPACE} ============================="
	@echo "==============================================================================================================="
	-oc get pods -l control-plane=controller-manager --namespace ${NAMESPACE} -o yaml
	@echo "==============================================================================================================="
	@echo "========================== ${DEPLOYMENT_NAME} deployment logs - Namespace: ${NAMESPACE} ============================="
	@echo "==============================================================================================================="
	-oc logs deployment.apps/${DEPLOYMENT_NAME} ${ADDITIONAL_PARAMS} --namespace ${NAMESPACE}
	@echo "==============================================================================================================="

.PHONY: setup-toolchainclusters
setup-toolchainclusters:
	$(MAKE) run-cicd-script SCRIPT_PATH=scripts/add-cluster.sh  SCRIPT_PARAMS="-t member -mn $(MEMBER_NS) -hn $(HOST_NS) -s"
	if [[ ${SECOND_MEMBER_MODE} == true ]]; then $(MAKE) run-cicd-script SCRIPT_PATH=scripts/add-cluster.sh  SCRIPT_PARAMS="-t member -mn $(MEMBER_NS_2) -hn $(HOST_NS) -s -mm 2"; fi
	$(MAKE) run-cicd-script SCRIPT_PATH=scripts/add-cluster.sh  SCRIPT_PARAMS="-t host   -mn $(MEMBER_NS)   -hn $(HOST_NS) -s"
	if [[ ${SECOND_MEMBER_MODE} == true ]]; then $(MAKE) run-cicd-script SCRIPT_PATH=scripts/add-cluster.sh  SCRIPT_PARAMS="-t host   -mn $(MEMBER_NS_2) -hn $(HOST_NS) -s -mm 2"; fi
	echo "Restart host operator pods so it can get the ToolchainCluster CRs while it's starting up".
	oc delete pods --namespace ${HOST_NS} -l control-plane=controller-manager


.PHONY: e2e-service-account
e2e-service-account:
ifeq ($(SETUP_E2E_SERVICE_ACCOUNTS),true)
	$(MAKE) run-cicd-script SCRIPT_PATH=scripts/add-cluster.sh  SCRIPT_PARAMS="-t member -tn e2e -mn $(MEMBER_NS) -hn $(HOST_NS) -s"
	$(MAKE) run-cicd-script SCRIPT_PATH=scripts/add-cluster.sh  SCRIPT_PARAMS="-t host -tn e2e -mn $(MEMBER_NS) -hn $(HOST_NS) -s"
	if [[ ${SECOND_MEMBER_MODE} == true ]]; then $(MAKE) run-cicd-script SCRIPT_PATH=scripts/add-cluster.sh  SCRIPT_PARAMS="-t member -tn e2e -mn $(MEMBER_NS_2) -hn $(HOST_NS) -s -mm 2"; fi
endif

###########################################################
#
# Fetching and building Member and Host Operators
#
###########################################################

.PHONY: publish-current-bundles-for-e2e
## Target that is supposed to be called from CI - it builds & publishes the current operator bundles
publish-current-bundles-for-e2e: get-and-publish-operators

.PHONY: get-and-publish-operators
get-and-publish-operators: PUBLISH_OPERATOR=true
get-and-publish-operators: INSTALL_OPERATOR=false
get-and-publish-operators: clean-e2e-files get-and-publish-host-operator get-and-publish-member-operator

.PHONY: get-publish-and-install-operators
get-publish-and-install-operators: get-and-publish-host-operator create-host-resources get-and-publish-member-operator

.PHONY: get-and-publish-member-operator
get-and-publish-member-operator:
ifneq (${MEMBER_NS_2},"")
    ifneq (${MEMBER_NS_2},)
		$(eval MEMBER_NS_2_PARAM = -mn2 ${MEMBER_NS_2})
    endif
endif
ifneq (${MEMBER_REPO_PATH},"")
    ifneq (${MEMBER_REPO_PATH},)
		$(eval MEMBER_REPO_PATH_PARAM = -mr ${MEMBER_REPO_PATH})
    endif
endif
	$(MAKE) run-cicd-script SCRIPT_PATH=scripts/ci/manage-member-operator.sh SCRIPT_PARAMS="-po ${PUBLISH_OPERATOR} -io ${INSTALL_OPERATOR} -mn ${MEMBER_NS} ${MEMBER_REPO_PATH_PARAM} -qn ${QUAY_NAMESPACE} -ds ${DATE_SUFFIX} -dl ${DEPLOY_LATEST} ${MEMBER_NS_2_PARAM}"

.PHONY: get-and-publish-host-operator
get-and-publish-host-operator:
ifneq (${REG_REPO_PATH},"")
    ifneq (${REG_REPO_PATH},)
		$(eval REG_REPO_PATH_PARAM = -rr ${REG_REPO_PATH})
    endif
endif
ifneq (${HOST_REPO_PATH},"")
    ifneq (${HOST_REPO_PATH},)
		$(eval HOST_REPO_PATH_PARAM = -hr ${HOST_REPO_PATH})
    endif
endif
	$(MAKE) run-cicd-script SCRIPT_PATH=scripts/ci/manage-host-operator.sh SCRIPT_PARAMS="-po ${PUBLISH_OPERATOR} -io ${INSTALL_OPERATOR} -hn ${HOST_NS} ${HOST_REPO_PATH_PARAM} -ds ${DATE_SUFFIX} -qn ${QUAY_NAMESPACE} -dl ${DEPLOY_LATEST} ${MEMBER_NS_2_PARAM} ${REG_REPO_PATH_PARAM}"

###########################################################
#
# Deploying Member and Host Operators in Openshift CI Environment
#
###########################################################

.PHONY: prepare-projects
prepare-projects: label-olm-ns create-host-project create-member1 create-member2

.PHONY: create-member1
create-member1:
	@echo "Preparing namespace for member operator: $(MEMBER_NS)..."
	$(MAKE) create-project PROJECT_NAME=${MEMBER_NS}
	-oc label ns --overwrite=true ${MEMBER_NS} app=member-operator

.PHONY: create-member2
create-member2:
ifeq ($(SECOND_MEMBER_MODE),true)
	@echo "Preparing namespace for second member operator: ${MEMBER_NS_2}..."
	$(MAKE) create-project PROJECT_NAME=${MEMBER_NS_2}
	-oc label ns --overwrite=true ${MEMBER_NS_2} app=member-operator
endif

.PHONY: deploy-host
deploy-host: create-host-project get-and-publish-host-operator create-host-resources

.PHONY: create-host-project
create-host-project:
	@echo "Preparing namespace for host operator ${HOST_NS}..."
	$(MAKE) create-project PROJECT_NAME=${HOST_NS}
	-oc label ns --overwrite=true ${HOST_NS} app=host-operator

.PHONY: create-host-resources
create-host-resources:
	# ignore if these resources already exist (nstemplatetiers may have already been created by operator)
	-oc create -f deploy/host-operator/${ENVIRONMENT}/ -n ${HOST_NS}
	# patch toolchainconfig to prevent webhook deploy for 2nd member, a 2nd webhook deploy causes the webhook verification in e2e tests to fail
	# since e2e environment has 2 member operators running in the same cluster
	if [[ ${SECOND_MEMBER_MODE} == true ]]; then \
		API_ENDPOINT=`oc get infrastructure cluster -o jsonpath='{.status.apiServerURL}'`; \
		TOOLCHAIN_CLUSTER_NAME=`echo "$${API_ENDPOINT}" | sed 's/.*api\.\([^:]*\):.*/\1/'`; \
		echo "API_ENDPOINT $${API_ENDPOINT}"; \
		echo "TOOLCHAIN_CLUSTER_NAME $${TOOLCHAIN_CLUSTER_NAME}"; \
		PATCH_FILE=/tmp/patch-toolchainconfig_${DATE_SUFFIX}.json; \
		echo "{\"spec\":{\"members\":{\"specificPerMemberCluster\":{\"member-$${TOOLCHAIN_CLUSTER_NAME}2\":{\"webhook\":{\"deploy\":false}}}}}}" > $$PATCH_FILE; \
		oc patch toolchainconfig config -n $(HOST_NS) --type=merge --patch "$$(cat $$PATCH_FILE)"; \
	fi;
	# delete registration-service pods in case they already exist
	oc delete pods --namespace ${HOST_NS} -l name=registration-service || true

.PHONY: create-has-application-crd
create-has-application-crd:
	oc apply -f deploy/member-operator/e2e-tests/

.PHONY: create-project
create-project:
	@-oc new-project ${PROJECT_NAME} 1>/dev/null
	@-oc project ${PROJECT_NAME}
	@-oc label ns --overwrite=true ${PROJECT_NAME} toolchain.dev.openshift.com/provider=codeready-toolchain
	@echo "adding network policies in $(PROJECT_NAME) namespace"
	@-oc process -p NAMESPACE=$(PROJECT_NAME) -f ${PWD}/make/resources/default-network-policies.yaml | oc apply -f -
	

.PHONY: display-eval
display-eval:
	@echo 'export HOST_NS=$(shell oc get projects -l app=host-operator --output=name -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort | tail -n 1)'
	@echo 'export MEMBER_NS=$(shell oc get projects -l app=member-operator --output=name -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort | tail -n 1)'
	@echo 'export REGISTRATION_SERVICE_NS=$$HOST_NS'
	@echo '# Run this command to configure your shell:'
	@echo '# eval $$(make display-eval)'


###########################################################
#
# Unit Tests (to verify the assertions and other utilities
# in the `testsupport` package)
#
###########################################################

.PHONY: test
## Run the unit tests in the 'testsupport/...' packages
test:
	@go test github.com/codeready-toolchain/toolchain-e2e/testsupport/... -failfast
