require_relative "test_helper"

class WhereTest < Minitest::Test
  def test_where
    now = Time.now
    store [
      {name: "Product A", store_id: 1, in_stock: true, backordered: true, created_at: now, orders_count: 4, user_ids: [1, 2, 3]},
      {name: "Product B", store_id: 2, in_stock: true, backordered: false, created_at: now - 1, orders_count: 3, user_ids: [1]},
      {name: "Product C", store_id: 3, in_stock: false, backordered: true, created_at: now - 2, orders_count: 2, user_ids: [1, 3]},
      {name: "Product D", store_id: 4, in_stock: false, backordered: false, created_at: now - 3, orders_count: 1}
    ]
    assert_search "product", ["Product A", "Product B"], where: {in_stock: true}

    # arrays
    assert_search "product", ["Product A"], where: {user_ids: 2}
    assert_search "product", ["Product A", "Product C"], where: {user_ids: [2, 3]}

    # due to precision
    unless cequel?
      # date
      assert_search "product", ["Product A"], where: {created_at: {gt: now - 1}}
      assert_search "product", ["Product A", "Product B"], where: {created_at: {gte: now - 1}}
      assert_search "product", ["Product D"], where: {created_at: {lt: now - 2}}
      assert_search "product", ["Product C", "Product D"], where: {created_at: {lte: now - 2}}
    end

    # integer
    assert_search "product", ["Product A"], where: {store_id: {lt: 2}}
    assert_search "product", ["Product A", "Product B"], where: {store_id: {lte: 2}}
    assert_search "product", ["Product D"], where: {store_id: {gt: 3}}
    assert_search "product", ["Product C", "Product D"], where: {store_id: {gte: 3}}

    # range
    assert_search "product", ["Product A", "Product B"], where: {store_id: 1..2}
    assert_search "product", ["Product A"], where: {store_id: 1...2}
    assert_search "product", ["Product A", "Product B"], where: {store_id: [1, 2]}
    assert_search "product", ["Product B", "Product C", "Product D"], where: {store_id: {not: 1}}
    assert_search "product", ["Product B", "Product C", "Product D"], where: {store_id: {_not: 1}}
    assert_search "product", ["Product C", "Product D"], where: {store_id: {not: [1, 2]}}
    assert_search "product", ["Product C", "Product D"], where: {store_id: {_not: [1, 2]}}
    assert_search "product", ["Product A"], where: {user_ids: {lte: 2, gte: 2}}
    assert_search "product", ["Product A", "Product B", "Product C", "Product D"], where: {store_id: -Float::INFINITY..Float::INFINITY}
    assert_search "product", ["Product C", "Product D"], where: {store_id: 3..Float::INFINITY}
    assert_search "product", ["Product A", "Product B"], where: {store_id: -Float::INFINITY..2}
    if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.6.0")
      # use eval to prevent parse error
      assert_search "product", ["Product C", "Product D"], where: {store_id: eval("3..")}
    end

    # or
    assert_search "product", ["Product A", "Product B", "Product C"], where: {or: [[{in_stock: true}, {store_id: 3}]]}
    assert_search "product", ["Product A", "Product B", "Product C"], where: {or: [[{orders_count: [2, 4]}, {store_id: [1, 2]}]]}
    assert_search "product", ["Product A", "Product D"], where: {or: [[{orders_count: 1}, {created_at: {gte: now - 1}, backordered: true}]]}

    # _or
    assert_search "product", ["Product A", "Product B", "Product C"], where: {_or: [{in_stock: true}, {store_id: 3}]}
    assert_search "product", ["Product A", "Product B", "Product C"], where: {_or: [{orders_count: [2, 4]}, {store_id: [1, 2]}]}
    assert_search "product", ["Product A", "Product D"], where: {_or: [{orders_count: 1}, {created_at: {gte: now - 1}, backordered: true}]}

    # _and
    assert_search "product", ["Product A"], where: {_and: [{in_stock: true}, {backordered: true}]}

    # _not
    assert_search "product", ["Product B", "Product C"], where: {_not: {_or: [{orders_count: 1}, {created_at: {gte: now - 1}, backordered: true}]}}

    # all
    assert_search "product", ["Product A", "Product C"], where: {user_ids: {all: [1, 3]}}
    assert_search "product", [], where: {user_ids: {all: [1, 2, 3, 4]}}

    # any / nested terms
    assert_search "product", ["Product B", "Product C"], where: {user_ids: {not: [2], in: [1, 3]}}
    assert_search "product", ["Product B", "Product C"], where: {user_ids: {_not: [2], in: [1, 3]}}

    # not
    assert_search "product", ["Product D"], where: {user_ids: nil}
    assert_search "product", ["Product A", "Product B", "Product C"], where: {user_ids: {not: nil}}
    assert_search "product", ["Product A", "Product B", "Product C"], where: {user_ids: {_not: nil}}
    assert_search "product", ["Product A", "Product C", "Product D"], where: {user_ids: [3, nil]}
    assert_search "product", ["Product B"], where: {user_ids: {not: [3, nil]}}
    assert_search "product", ["Product B"], where: {user_ids: {_not: [3, nil]}}
  end

  def test_where_string_operators
    error = assert_raises RuntimeError do
      assert_search "product", [], where: {store_id: {"lt" => 2}}
    end
    assert_includes error.message, "Unknown where operator"
  end

  def test_unknown_operator
    error = assert_raises RuntimeError do
      assert_search "product", [], where: {store_id: {contains: "%2%"}}
    end
    assert_includes error.message, "Unknown where operator"
  end

  def test_regexp
    store_names ["Product A"]
    assert_search "*", ["Product A"], where: {name: /\APro.+\z/}
  end

  def test_alternate_regexp
    store_names ["Product A", "Item B"]
    assert_search "*", ["Product A"], where: {name: {regexp: "Pro.+"}}
  end

  def test_special_regexp
    store_names ["Product <A>", "Item <B>"]
    assert_search "*", ["Product <A>"], where: {name: /\APro.+<.+\z/}
  end

  def test_regexp_not_anchored
    store_names ["abcde"]
    # regular expressions are always anchored right now
    # TODO change in future release
    assert_warns "Regular expressions are always anchored in Elasticsearch" do
      assert_search "*", [], where: {name: /abcd/}
    end
    assert_warns "Regular expressions are always anchored in Elasticsearch" do
      assert_search "*", [], where: {name: /bcde/}
    end
    assert_warns "Regular expressions are always anchored in Elasticsearch" do
      assert_search "*", ["abcde"], where: {name: /abcde/}
    end
    assert_warns "Regular expressions are always anchored in Elasticsearch" do
      assert_search "*", ["abcde"], where: {name: /.*bcd.*/}
    end
  end

  def test_regexp_anchored
    store_names ["abcde"]
    assert_search "*", ["abcde"], where: {name: /\Aabcde\z/}
    assert_warns "Regular expressions are always anchored in Elasticsearch" do
      assert_search "*", [], where: {name: /\Abcd/}
    end
    assert_warns "Regular expressions are always anchored in Elasticsearch" do
      assert_search "*", [], where: {name: /bcd\z/}
    end
  end

  def test_regexp_case
    store_names ["abcde"]
    assert_search "*", [], where: {name: /\AABCDE\z/}
    unless case_insensitive_supported?
      assert_warns "Case-insensitive flag does not work with Elasticsearch < 7.10" do
        assert_search "*", [], where: {name: /\AABCDE\z/i}
      end
    else
      assert_search "*", ["abcde"], where: {name: /\AABCDE\z/i}
    end
  end

  def test_prefix
    store_names ["Product A", "Product B", "Item C"]
    assert_search "*", ["Product A", "Product B"], where: {name: {prefix: "Pro"}}
  end

  def test_exists
    store [
      {name: "Product A", user_ids: [1, 2]},
      {name: "Product B"}
    ]
    assert_search "product", ["Product A"], where: {user_ids: {exists: true}}
  end

  def test_like
    store_names ["Product ABC", "Product DEF"]
    assert_search "product", ["Product ABC"], where: {name: {like: "%ABC%"}}
    assert_search "product", ["Product ABC"], where: {name: {like: "%ABC"}}
    assert_search "product", [], where: {name: {like: "ABC"}}
    assert_search "product", [], where: {name: {like: "ABC%"}}
    assert_search "product", [], where: {name: {like: "ABC%"}}
    assert_search "product", ["Product ABC"], where: {name: {like: "Product_ABC"}}
  end

  def test_like_escape
    store_names ["Product 100%", "Product 1000"]
    assert_search "product", ["Product 100%"], where: {name: {like: "% 100\\%"}}
  end

  def test_like_special_characters
    store_names [
      "Product ABC", "Product.ABC", "Product?ABC", "Product+ABC", "Product*ABC", "Product|ABC",
      "Product{ABC}", "Product[ABC]", "Product(ABC)",  "Product\"ABC\"", "Product\\ABC"
    ]
    assert_search "*", ["Product.ABC"], where: {name: {like: "Product.A%"}}
    assert_search "*", ["Product?ABC"], where: {name: {like: "Product?A%"}}
    assert_search "*", ["Product+ABC"], where: {name: {like: "Product+A%"}}
    assert_search "*", ["Product*ABC"], where: {name: {like: "Product*A%"}}
    assert_search "*", ["Product|ABC"], where: {name: {like: "Product|A%"}}
    assert_search "*", ["Product{ABC}"], where: {name: {like: "%{ABC}"}}
    assert_search "*", ["Product[ABC]"], where: {name: {like: "%[ABC]"}}
    assert_search "*", ["Product(ABC)"], where: {name: {like: "%(ABC)"}}
    assert_search "*", ["Product\"ABC\""], where: {name: {like: "%\"ABC\""}}
    assert_search "*", ["Product\\ABC"], where: {name: {like: "Product\\A%"}}
  end

  def test_like_optional_operators
    store_names ["Product A&B", "Product B", "Product <3", "Product @Home"]
    assert_search "product", ["Product A&B"], where: {name: {like: "%A&B"}}
    assert_search "product", ["Product <3"], where: {name: {like: "%<%"}}
    assert_search "product", ["Product @Home"], where: {name: {like: "%@Home%"}}
  end

  def test_ilike
    if case_insensitive_supported?
      store_names ["Product ABC", "Product DEF"]
      assert_search "product", ["Product ABC"], where: {name: {ilike: "%abc%"}}
      assert_search "product", ["Product ABC"], where: {name: {ilike: "%abc"}}
      assert_search "product", [], where: {name: {ilike: "abc"}}
      assert_search "product", [], where: {name: {ilike: "abc%"}}
      assert_search "product", [], where: {name: {ilike: "abc%"}}
      assert_search "product", ["Product ABC"], where: {name: {ilike: "Product_abc"}}
    else
      error = assert_raises(ArgumentError) do
        Product.search("*", where: {name: {ilike: "%abc%"}})
      end
      assert_equal "ilike requires Elasticsearch 7.10+", error.message
    end
  end

  def test_ilike_escape
    skip unless case_insensitive_supported?

    store_names ["Product 100%", "Product B"]
    assert_search "product", ["Product 100%"], where: {name: {ilike: "% 100\\%"}}
  end

  def test_ilike_special_characters
    skip unless case_insensitive_supported?

    store_names ["Product ABC\"", "Product B"]
    assert_search "product", ["Product ABC\""], where: {name: {ilike: "%abc\""}}
  end

  def test_ilike_optional_operators
    skip unless case_insensitive_supported?

    store_names ["Product A&B", "Product B", "Product <3", "Product @Home"]
    assert_search "product", ["Product A&B"], where: {name: {ilike: "%a&b"}}
    assert_search "product", ["Product <3"], where: {name: {ilike: "%<%"}}
    assert_search "product", ["Product @Home"], where: {name: {ilike: "%@home%"}}
  end

  # def test_script
  #   store [
  #     {name: "Product A", store_id: 1},
  #     {name: "Product B", store_id: 10}
  #   ]
  #   assert_search "product", ["Product A"], where: {_script: "doc['store_id'].value < 10"}
  # end

  def test_where_string
    store [
      {name: "Product A", color: "RED"}
    ]
    assert_search "product", ["Product A"], where: {color: "RED"}
  end

  def test_where_nil
    store [
      {name: "Product A"},
      {name: "Product B", color: "red"}
    ]
    assert_search "product", ["Product A"], where: {color: nil}
  end

  def test_where_id
    store_names ["Product A"]
    product = Product.first
    assert_search "product", ["Product A"], where: {id: product.id.to_s}
  end

  def test_where_empty
    store_names ["Product A"]
    assert_search "product", ["Product A"], where: {}
  end

  def test_where_empty_array
    store_names ["Product A"]
    assert_search "product", [], where: {store_id: []}
  end

  # http://elasticsearch-users.115913.n3.nabble.com/Numeric-range-quey-or-filter-in-an-array-field-possible-or-not-td4042967.html
  # https://gist.github.com/jprante/7099463
  def test_where_range_array
    store [
      {name: "Product A", user_ids: [11, 23, 13, 16, 17, 23]},
      {name: "Product B", user_ids: [1, 2, 3, 4, 5, 6, 7, 8, 9]},
      {name: "Product C", user_ids: [101, 230, 150, 200]}
    ]
    assert_search "product", ["Product A"], where: {user_ids: {gt: 10, lt: 24}}
  end

  def test_where_range_array_again
    store [
      {name: "Product A", user_ids: [19, 32, 42]},
      {name: "Product B", user_ids: [13, 40, 52]}
    ]
    assert_search "product", ["Product A"], where: {user_ids: {gt: 26, lt: 36}}
  end

  def test_near
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", ["San Francisco"], where: {location: {near: [37.5, -122.5]}}
  end

  def test_near_hash
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", ["San Francisco"], where: {location: {near: {lat: 37.5, lon: -122.5}}}
  end

  def test_near_within
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000},
      {name: "San Marino", latitude: 43.9333, longitude: 12.4667}
    ]
    assert_search "san", ["San Francisco", "San Antonio"], where: {location: {near: [37, -122], within: "2000mi"}}
  end

  def test_near_within_hash
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000},
      {name: "San Marino", latitude: 43.9333, longitude: 12.4667}
    ]
    assert_search "san", ["San Francisco", "San Antonio"], where: {location: {near: {lat: 37, lon: -122}, within: "2000mi"}}
  end

  def test_geo_polygon
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000},
      {name: "San Marino", latitude: 43.9333, longitude: 12.4667}
    ]
    polygon = [
      {lat: 42.185695, lon: -125.496146},
      {lat: 42.185695, lon: -94.125535},
      {lat: 27.122789, lon: -94.125535},
      {lat: 27.12278, lon: -125.496146}
    ]
    _, stderr = capture_io do
      assert_search "san", ["San Francisco", "San Antonio"], where: {location: {geo_polygon: {points: polygon}}}
    end
    unless Searchkick.server_below?("7.12.0")
      assert_match "Deprecated field [geo_polygon] used", stderr
    end

    # Field [location] is not of type [geo_shape] but of type [geo_point] error for previous versions
    unless Searchkick.server_below?("7.14.0")
      polygon << polygon.first
      # see test/geo_shape_test.rb for other geo_shape tests
      assert_search "san", ["San Francisco", "San Antonio"], where: {location: {geo_shape: {type: "polygon", coordinates: [polygon]}}}
    end
  end

  def test_top_left_bottom_right
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", ["San Francisco"], where: {location: {top_left: [38, -123], bottom_right: [37, -122]}}
  end

  def test_top_left_bottom_right_hash
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", ["San Francisco"], where: {location: {top_left: {lat: 38, lon: -123}, bottom_right: {lat: 37, lon: -122}}}
  end

  def test_top_right_bottom_left
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", ["San Francisco"], where: {location: {top_right: [38, -122], bottom_left: [37, -123]}}
  end

  def test_top_right_bottom_left_hash
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", ["San Francisco"], where: {location: {top_right: {lat: 38, lon: -122}, bottom_left: {lat: 37, lon: -123}}}
  end

  def test_multiple_locations
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", ["San Francisco"], where: {multiple_locations: {near: [37.5, -122.5]}}
  end

  def test_multiple_locations_with_term_filter
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", [], where: {multiple_locations: {near: [37.5, -122.5]}, name: "San Antonio"}
    assert_search "san", ["San Francisco"], where: {multiple_locations: {near: [37.5, -122.5]}, name: "San Francisco"}
  end

  def test_multiple_locations_hash
    store [
      {name: "San Francisco", latitude: 37.7833, longitude: -122.4167},
      {name: "San Antonio", latitude: 29.4167, longitude: -98.5000}
    ]
    assert_search "san", ["San Francisco"], where: {multiple_locations: {near: {lat: 37.5, lon: -122.5}}}
  end

  def test_nested
    store [
      {name: "Product A", details: {year: 2016}}
    ]
    assert_search "product", ["Product A"], where: {"details.year" => 2016}
  end

  def case_insensitive_supported?
    !Searchkick.server_below?("7.10.0")
  end
end
