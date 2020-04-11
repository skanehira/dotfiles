if err := json.NewDecoder({{_input_:reader}}).Decode({{_input_:target}}); err != nil {
	log.Fatal(err)
}
