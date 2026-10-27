.PHONY: app run test install release publish clean

app:            ## Build build/LightsOut.app (release)
	./scripts/build-app.sh release

run: app        ## Build and launch
	pkill -x LightsOut || true
	open build/LightsOut.app

test:           ## Run the unit tests
	swift test

install: app    ## Copy to /Applications and launch (enables Launch at Login)
	pkill -x LightsOut || true
	rm -rf /Applications/LightsOut.app && cp -R build/LightsOut.app /Applications/
	open /Applications/LightsOut.app

release: app    ## Developer ID sign, notarize and pack → build/LightsOut.dmg, write the appcast
	./scripts/release.sh

publish:        ## Upload the GitHub release, then deploy the site and appcast
	./scripts/publish.sh

clean:
	rm -rf build .build
