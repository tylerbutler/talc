import {
  parse_positive, keep_thing, person_name, Person$Person,
  result_to_option, external_greeting, identity,
} from "basic_gleam_package";
import { add } from "basic_gleam_package/math";
import { Result$Ok, Result$Error } from "basic_gleam_package/gleam";

const result = parse_positive("42");
const thing = keep_thing({ value: 7 });
const name: string = person_name(Person$Person("Ada"));
const sum: number = add(1, 2);
const greeting: string = external_greeting("World");
const value: number = identity(42);
result_to_option(Result$Ok(42));
result_to_option(Result$Error("error"));

// @ts-expect-error Gleam Int requires a number.
identity("42");
// @ts-expect-error A plain object is not a native Result.
result_to_option({ value: 42 });
// @ts-expect-error External Thing's value must match Thing(Int).
keep_thing({ value: "seven" });

void [result, thing, name, sum, greeting, value];
