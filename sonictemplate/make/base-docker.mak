select_container=$$(docker ps -a | sed 1d | fzf | awk "{print \$$1}")
select_image=$$(docker images | grep -v "<none>" | sed 1d | fzf | awk "{print \$$1}")

build:
	docker build -t {{_input_:image}}

prune:
	docker image prune

start:
	docker start ${select_container}

stop:
	docker stop ${select_container}

kill:
	docker kill ${select_container}

image-remove:
	docker rmi ${select_image}

container-remove:
	docker rm ${select_container}
