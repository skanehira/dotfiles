if err := json.NewEncoder({{_input_:writer}}).Encode({{_input_:target}}); err != nil {
	log.Fatal(err)
}
