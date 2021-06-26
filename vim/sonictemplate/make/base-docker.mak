select_container=$$(docker ps -a | sed 1d | fzf | awk "{print \$$1}")
select_image=$$(docker images | grep -v "<none>" | sed 1d | fzf | awk "{print \$$1}")
select_running_container=$$(docker ps | sed 1d | fzf | awk "{print \$$1}")

.PHONY: build
build:
	@docker build -t {{_input_:image}}

.PHONY: prune
prune:
	@docker image prune

.PHONY: start
start:
	@docker start ${select_container}

.PHONY: stop
stop:
	@docker stop ${select_running_container}

.PHONY: kill
kill:
	@docker kill ${select_running_container}

.PHONY: image-remove
image-remove:
	@docker rmi ${select_image}

.PHONY: container-remove
container-remove:
	@docker rm ${select_container}

.PHONY: attach
attach:
	@for c in ${select_running_container}; do \
		tmux split-window docker exec -it $$c sh; \
	done
