build:
	docker build -t {{_input_:image}}

prune:
	docker image prune

