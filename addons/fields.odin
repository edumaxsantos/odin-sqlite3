package addons

import "core:mem"
import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:testing"

Field_Error :: Maybe(string)

@(private)
Field_Type :: struct {
	name:   string,
	type:   ^reflect.Type_Info,
	tag:    string,
	offset: int,
}

@(private)
write_struct_field :: proc(obj: ^$T, field: Field_Type, value: $E) -> Field_Error {
    value := value
    value_bytes := reflect.as_bytes(value)

    if field.type.id != typeid_of(E) || len(value_bytes) != field.type.size {
        return fmt.tprintf(
            "given field {}.{} ({}) is {} bytes, but value {} is {} bytes",
            typeid_of(T), field.name, field.type.id, field.type.size, typeid_of(E), len(value_bytes),
        )
    }

    obj_bytes := mem.ptr_to_bytes(obj)
    copy(obj_bytes[field.offset:], value_bytes)

    return nil
}

@(test)
write_struct_field_test :: proc(t: ^testing.T) {
	S :: struct($T: typeid) {
		padding1: [13]u8 `sqlite:"Padding1"`,
		value:    T `sqlite:"Value"`,
		padding2: [5]u8 `sqlite:"Padding2"`,
	}
	obj: S(string)

	fields, err := get_type_fields(S(string))
	testing.expect(t, err == nil)
	defer delete_field_types(fields)

	testing.expect(t, fields[0].tag == "Padding1")
	testing.expect(t, fields[0].name == "padding1")
	testing.expect(t, fields[0].type.id == typeid_of([13]u8))

	testing.expect(t, fields[1].tag == "Value")
	testing.expect(t, fields[1].name == "value")
	testing.expect(t, fields[1].type.id == typeid_of(string))

	testing.expect(t, fields[2].tag == "Padding2")
	testing.expect(t, fields[2].name == "padding2")
	testing.expect(t, fields[2].type.id == typeid_of([5]u8))

	arr := [13]u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}

	err = write_struct_field(&obj, fields[0], arr)

	test_using_type :: proc(t: ^testing.T, value: $T) {
		S1 :: S(T)
		fields, err := get_type_fields(S1)
		testing.expect(t, err == nil)
		defer delete_field_types(fields)

		value_field := fields[1]
		obj: S1

		err = write_struct_field(&obj, value_field, value)
		testing.expect(t, err == nil)
		testing.expect_value(t, obj.value, value)

		// neighbours are unchanged
		for b in obj.padding1 {
			testing.expect(t, b == 0)
		}

		// neighbours are unchanged
		for b in obj.padding2 {
			testing.expect(t, b == 0)
		}
	}

	test_using_type(t, u8(100))
	test_using_type(t, i8(100))
	test_using_type(t, true)
	test_using_type(t, i16(100))
	test_using_type(t, u16(100))
	test_using_type(t, i32(100))
	test_using_type(t, u32(100))
	test_using_type(t, i64(100))
	test_using_type(t, u64(100))
	test_using_type(t, "hello")
}

@(private)
field_type_deinit :: proc(field: ^Field_Type) {
	delete(field.name)
	delete(field.tag)
}

@(private)
delete_field_types :: proc(field_types: []Field_Type) {
	for &it in field_types {
		field_type_deinit(&it)
	}

	delete(field_types)
}

@(private)
@(require_results)
get_type_fields :: proc($T: typeid) -> ([]Field_Type, Field_Error) {
	out: [dynamic]Field_Type
	struct_info := type_info_of(T)
	for i in 0 ..< reflect.struct_field_count(T) {
		field := reflect.struct_field_at(T, i)
		capture, err := match_and_return_capture(`sqlite:"(.*?)"`, cast(string)field.tag)
		if err != nil {
			defer delete_field_types(out[:])

			return nil, fmt.tprintf(
				"could not find sqlite tag on field '{}' of struct '{}'. err: {}",
				field.name,
				struct_info,
				err,
			)
		}

		append(
			&out,
			Field_Type {
				tag = capture,
				name = strings.clone(field.name),
				type = field.type,
				offset = int(field.offset),
			},
		)

	}

	return out[:], nil
}


@(test)
get_type_fields_test__all_ok :: proc(t: ^testing.T) {
	S :: struct {
		a: int `sqlite:"Foo"`,
		b: bool `sqlite:"Bar"`,
		c: string `sqlite:"Foobar"`,
	}

	fields, err := get_type_fields(S)
	testing.expect(t, err == nil)
	defer delete_field_types(fields)

	testing.expect(t, fields[0].tag == "Foo")
	testing.expect(t, fields[0].name == "a")
	testing.expect(t, fields[0].type.id == typeid_of(int))

	testing.expect(t, fields[1].tag == "Bar")
	testing.expect(t, fields[1].name == "b")
	testing.expect(t, fields[1].type.id == typeid_of(bool))

	testing.expect(t, fields[2].tag == "Foobar")
	testing.expect(t, fields[2].name == "c")
	testing.expect(t, fields[2].type.id == typeid_of(string))
}


@(test)
get_type_fields_test__missing_tag :: proc(t: ^testing.T) {
	S :: struct {
		a: int `sqlite:"Foo"`,
		b: bool,
		c: string `sqlite:"Foobar"`,
	}

	fields, err := get_type_fields(S)
	testing.expect(t, err != nil)
}


@(test)
get_type_fields_test__malformed_tag :: proc(t: ^testing.T) {
	S :: struct {
		a: int `sqlite:"Foo"`,
		b: bool `sqlit:"Bar"`,
		c: string `sqlite:"Foobar"`,
	}

	fields, err := get_type_fields(S)
	testing.expect(t, err != nil)
}

@(test)
get_type_fields_test__malformed_tag_missing_quote :: proc(t: ^testing.T) {
	S :: struct {
		a: int `sqlite:"Foo"`,
		b: bool `sqlite:"Bar`,
		c: string `sqlite:"Foobar"`,
	}

	fields, err := get_type_fields(S)
	testing.expect(t, err != nil)
}

@(test)
write_struct_field_test__fixed_array_into_matching_field :: proc(t: ^testing.T) {
    S :: struct {
        blob: [5]byte `sqlite:"blob"`,
    }

    obj: S
    arr := [5]byte{55, 23, 10, 4, 34}
    fields, err := get_type_fields(S)
    testing.expect(t, err == nil)
    defer delete_field_types(fields)

    werr := write_struct_field(&obj, fields[0], arr)
    testing.expect(t, werr == nil, fmt.aprintf("Got an error on write struct field. %s", werr, allocator = context.temp_allocator))
    testing.expect_value(t, obj.blob[0], 55)
    testing.expect_value(t, obj.blob[1], 23)
    testing.expect_value(t, obj.blob[4], 34)
}


@(test)
write_struct_field_test__fixed_array_wrong_length :: proc(t: ^testing.T) {
	S :: struct {
	    blob: [5]byte `sqlite:"blob"`,
	}
	obj: S

	arr := [4]byte{1, 2, 3, 4}

	fields, err := get_type_fields(S)
	testing.expect(t, err == nil)
	defer delete_field_types(fields)

	werr := write_struct_field(&obj, fields[0], arr)
	testing.expect(t, werr != nil)
	testing.expect(t, strings.contains(werr.(string), "[5]"))
	testing.expect(t, strings.contains(werr.(string), "[4]"))
	testing.expect_value(t, obj.blob[0], 0)
	testing.expect_value(t, obj.blob[4], 0)
}

@(test)
write_struct_field_test__slice :: proc(t: ^testing.T) {
	S :: struct {
		pad: []u8 `sqlite:"Pad"`, // slice has 16
		after: u8 `sqlite:"After"`,
	}
	obj: S

	fields, err := get_type_fields(S)
	testing.expect(t, err == nil)
	defer delete_field_types(fields)

	arr := [13]u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}
	werr := write_struct_field(&obj, fields[0], arr[:])
	testing.expect(t, werr == nil)
	testing.expect_value(t, len(obj.pad[:]), len(arr[:]))
	testing.expect_value(t, obj.after, 0)
}
