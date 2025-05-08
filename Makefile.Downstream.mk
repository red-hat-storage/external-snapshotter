# defining variables here before including "Makefile" makes these variables unique for current makefile
IMAGE_REGISTRY ?= quay.io
REGISTRY_NAME ?= ocs-dev
IMAGE_TAG ?= latest
IMAGE_NAME ?= snapshot-controller

BUNDLE_IMAGE_NAME ?= $(IMAGE_NAME)-bundle

BUNDLE_IMG ?= $(IMAGE_REGISTRY)/$(REGISTRY_NAME)/$(BUNDLE_IMAGE_NAME):$(IMAGE_TAG)

# the PACKAGE_NAME is included in the bundle/CSV and is used in catalogsources
# for operators (like OperatorHub.io). Products that include the ceph-csi-operator
# bundle should use a different PACKAGE_NAME to prevent conflicts.
PACKAGE_NAME ?= odf-snapshot-controller

# Creating the New CatalogSource requires publishing CSVs that replace one operator,
# but can skip several. This can be accomplished using the skipRange annotation:
SKIP_RANGE ?=

# The default version of the bundle (CSV) can be found in
# config/manifests/bases/cephcsi-operator.clusterserviceversion.yaml
BUNDLE_VERSION ?= 4.20.0

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
DEFAULT_CHANNEL ?= alpha
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "preview,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=preview,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="preview,fast,stable")
CHANNELS ?= $(DEFAULT_CHANNEL)
BUNDLE_CHANNELS := --channels=$(CHANNELS)

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk-$(OPERATOR_SDK_VERSION)
KUSTOMIZE ?= $(LOCALBIN)/kustomize-$(KUSTOMIZE_VERSION)

OPERATOR_SDK_VERSION ?= 1.34.1
KUSTOMIZE_VERSION ?= v5.3.0

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))


.PHONY: bundle
bundle: kustomize operator-sdk
	rm -rf bundle
	sed 's/@PACKAGE_NAME@/$(PACKAGE_NAME)/g;s/@SKIP_RANGE@/"$(SKIP_RANGE)"/g;s/@REPLACES@/"$(REPLACES)"/g;s/@BUNDLE_VERSION@/$(BUNDLE_VERSION)/g' \
	< config/manifests/bases/clusterserviceversion.yaml.in > config/manifests/bases/$(PACKAGE_NAME).clusterserviceversion.yaml
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle \
		--overwrite --manifests --metadata --package $(PACKAGE_NAME) --version $(BUNDLE_VERSION)
	hack/update-csv-timestamp.sh

.PHONY: bundle-build
bundle-build: bundle ## Build the bundle image.
	$(CONTAINER_TOOL) build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push bundle image with the manager.
	$(CONTAINER_TOOL) push $(BUNDLE_IMG)

.PHONY: operator-sdk
operator-sdk: ## Download operator-sdk locally.
	@test -f $(OPERATOR_SDK) && echo "$(OPERATOR_SDK) already exists. Skipping download." && exit 0 ;\
	echo "Downloading $(OPERATOR_SDK)" ;\
        set -e ;\
        mkdir -p $(dir $(OPERATOR_SDK)) ;\
        OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
        curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/v${OPERATOR_SDK_VERSION}/operator-sdk_$${OS}_$${ARCH} ;\
        chmod +x $(OPERATOR_SDK)

# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary (ideally with version)
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f $(1) ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
GOBIN=$(LOCALBIN) go install $${package} ;\
mv "$$(echo "$(1)" | sed "s/-$(3)$$//")" $(1) ;\
}
endef
