# Used to generate a diff between two JSON objects, and also transform a diff with respect to another diff
#
# Generally when we diff two objects A and B, the diff can be thought of as, what are the operations needed to perform on A, to create an object identical to B
# So B can be thought of as the target object, A is the origin object
#
#### Example 1:
#
#     A = { 'num' : 5 }
#     B = { 'num' : 6 }
#
# The `diff(A,B)` should specify an operation to add 1 to the value of the object key 'num'
#
# We specify the diffs as a map of keys to operations.  An operation consists of 'o': specifies the kind/type of operation and 'v': a value or parameter for the operation
# The 'v' is a parameter for the specified operation, in cases where the operation doesn't need a parameter, it might be omitted.
# Currently this only happens when o = '-', which means, we are deleting a key, no parameter is necessary.
#
# For the two example objects above, the diff would be:
#
#     {
#      'num' : {'o':'I', 'v':1}
#     }
#
# For the key 'num', it defines an operation, the 'o' = 'I' specifies to treat the value of the subsequent 'v' as the parameter in an integer diff
# For integer diffs,
#   When generating the diff, to obtain the 'v' used in the operation, we just substract the value of the key of the origin object from the value of the key from the target object
#   In other words, to get the 'v', we just do B.num - A.num, or 6-5
#
#   If we then applied this diff to A, because the 'o' is 'I' for integer, we know to just add the value of 'v' to A.num to get 6
#
#
#### Example 2:
#
#
#     A = { 'numbers' : [1, 3, 2, 3, 4],
#           'name' : 'Ted'
#          }
#     B = { 'numbers' : [1, 2, 3, 4],
#           'name' : 'Red'
#          }
#
# The `diff(A,B)` should be two main operations, one to somehow rearrange the array in numbers, to match the second array.  There are a number of different ways we could do this.
# And the second should be to change the first letter of T to R in name - we don't care exactly how since DiffMatchPatch will take care of it. The value of the operation then is just the output of DMP.
#
# Diff for array
#
# When generating the diff, we see that the value of numbers is an array so we will call `list_diff()` to generate the diff for that portion.
#
#     a = [1, 3, 2, 3, 4]
#     b = [1, 2, 3, 4]
#
# The most naive approach we could do is to compare directly each index of the array, and when it is different, add an operation to change the value for that index.
#
# For the above, we could do a series of operations like,
#
#     Change a[1] to 2,
#     Change a[2] to 3,
#     Change a[3] to 4,
#     Delete a[4]
#
# But the most efficient thing we could do is just to delete a[1]
# We can optimize the operations generated by doing some work beforehand, like removing the common prefix/suffixes.
# If we remove the common prefix/suffix, the resulting arrays are:
#
#     [3]
#     []
#
# Now if we do the diff, we know we only need to delete 3 (a[1])
#
# There are many more optimizations on [Neil Fraser's page](http://neil.fraser.name/writing/diff/), but currently that is the only one we do.
#
# The delete a[1] will look like: '1' : {'o':'-'}
# We use similar notation for arrays as objects. Where the keys are indexes.
# That says at array index 1, we have a delete operation ('o' = '-'), since it is delete there is no parameter and no 'v'
# That is the output of the `list_diff()` then, {'1': {'o' : '-'}}
# When we apply that diff to array a, we know to go to index 1, do that operation (delete)
#
# Back to the example, the diff for the 'numbers' key will first be 'o':'L' , with 'v', the value being the output of the `list_diff()` function.
# That portion of the diff for 'numbers' will look like:
#
#     {'numbers' : {'o':'L',
#                   'v': [output of list diff]
#                  }
#     }
#
# or
#
#     {'numbers' : {'o':'L',
#                   'v': {'1': {'o' : '-'}}
#                  }
#     }
#
# Now we move on to the next key, 'name'.  We check the value and see that it is a string. For strings we automatically use diffmatchpatch.
# When generating the diff, we set 'o' to 'd', so we know later to use DMP, and the value 'v' is the output of DMP diff (in DMP terms generating a delta)
#
# This looks like:
#
#     {'o':'d', 'v':'-1\t+R\t=2'}
#
# So the diff for the 'name' key is:
#
#     {'name': {'o':'d', 'v':'-1\t+R\t=2'}}
#
# Now the diff for the whole object is all the diffs for all the keys.
#
#     {'numbers' : {'o': 'L', 'v': {'1': {'o': '-'}}},
#      'name'    : {'o': 'd', 'v': '-1\t+R\t=2'}}
#
# We can use that as a parameter to `apply_obj_diff(A, diff)`, which would apply the above diff to object A (defined at top of example),
# The output of that `apply_obj_diff(A, diff)` then should be an object identical to B.

#### Main documentation
class jsondiff
  @dmp = new diff_match_patch()

  #### Helper functions

  # Return the number of entries in an object
  entries: (obj) =>
    n = 0
    for own key, value of obj
      n++
    n

  # Get the type properly, javascripts `typeof` is broken, see [http://javascript.crockford.com/remedial.html]().
  typeOf: (value) =>
    s = typeof value
    if s is 'object'
      if value
        if typeof value.length is 'number' and
          typeof value.splice is 'function' and
          not value.propertyIsEnumerable 'length'
            s = 'array'
      else
        s = 'null'
    return s

  # Return a deep copy of the object
  deepCopy: (obj) =>
    if Object::toString.call(obj) is '[object Array]'
      out = []
      for i in [0...obj.length]
        out[i] = arguments.callee obj[i]
      return out
    if typeof obj is 'object'
      out = {}
      for i of obj
        out[i] = arguments.callee obj[i]
      return out
    return obj

  # Deep equals comparison
  equals: (a, b) =>
    typea = @typeOf a
    typeb = @typeOf b
    if typea is 'boolean' and typeb is 'number'
        return Number(a) is b
    if typea is 'number' and typeb is 'boolean'
        return Number(b) is a
    if typea != typeb
      return false
    if typea is 'array'
      return @list_equals a, b
    else if typea is 'object'
      return @object_equals a, b
    else
      return a is b

  # Given two arrays, returns true if all elements of array are equal
  list_equals: (a, b) =>
    alength = a.length
    if alength != b.length
      return false
    for i in [0...alength]
      if not @equals a[i], b[i]
        return false
    return true

  # Given two objects, returns true if both objects have same set of keys and values
  object_equals: (a, b) =>
    for own key of a
      if not (key of b)
        return false
      if not @equals a[key], b[key]
        return false
    for own key of b
      if not (key of a)
        return false
    return true

  # Returns the length of common elements at beginning of two arrays
  _common_prefix: (a, b) =>
    minlen = Math.min a.length, b.length
    for i in [0...minlen]
      if not @equals a[i], b[i]
        return i
    return minlen

  # Returns the length of common elements at end of two arrays
  _common_suffix: (a, b) =>
    lena = a.length
    lenb = b.length
    minlen = Math.min a.length, b.length
    if minlen is 0
      return 0
    for i in [0...minlen]
      if not @equals a[lena-i-1], b[lenb-i-1]
        return i
    return minlen

# Compare two arrays and generate a diff object to be applied to an array.
# For arrays we treat them like objects, in an object we have explicit mapping of keys : values.
# The same format is used for arrays, where we replace the key with the index.
#
# For example, if we have the objects:
#
#     A = { 'num1' : 4, 'num2' : 7 }
#     B = { 'num1' : 8, 'num2' : 2 }
#
# The `diff(A,B)` would be
#
#     { 'num1' : {'o':'I', 'v':4},
#       'num2' : {'o':'I', 'v':-5} }
#
# Similarly, if we have an array instead with the same values:
#
#     A = [4, 7]
#     B = [8, 2]
#
# The diff would be:
#
#     { '0' : {'o':'I', 'v':4},
#       '1' : {'o':'I', 'v':-5} }
  list_diff: (a, b) =>
    diffs = {}
    lena = a.length
    lenb = b.length

    prefix_len = @_common_prefix a, b
    suffix_len = @_common_suffix a, b

    a = a[prefix_len...lena-suffix_len]
    b = b[prefix_len...lenb-suffix_len]

    lena = a.length
    lenb = b.length

    maxlen = Math.max lena, lenb

    # Iterate over both arrays
    for i in [0..maxlen]
      if i < lena and i < lenb
        # If values aren't equal we set the value to be the output of the diff
        if not @equals a[i], b[i]
          diffs[i+prefix_len] = @diff a[i], b[i]
      else if i < lena
        # array b doesn't have this element so remove it
        diffs[i+prefix_len] = {'o':'-'}
      else if i < lenb
        # array a doesn't have this element so add it
        diffs[i+prefix_len] = {'o':'+', 'v':b[i]}

    return diffs

  list_diff_dmp: (a, b) =>
    lena = a.length
    lenb = b.length
    atext = @_serialize_to_text a
    btext = @_serialize_to_text b

    diffs = jsondiff.dmp.diff_lineMode_ atext, btext
    jsondiff.dmp.diff_cleanupEfficiency(diffs)
    delta = jsondiff.dmp.diff_toDelta(diffs)
    return delta

  _serialize_to_text: (a) =>
    s = ''
    lena = a.length
    for i in [0..lena-1]
      s += "#{JSON.stringify a[i]}\n"
    return s

  # FIXME: elements may be strings and contain \n
  _text_to_array: (s) =>
    a = []
    sa = s.split("\n")
    a = (JSON.parse(x) for x in sa when x.length > 0)
    return a

# Compare two objects and generate a diff object to be applied to an object (dictionary).
  object_diff: (a, b) =>
    diffs = {}
    if not a? or not b? then return {}
    for own key of a
      if key of b
        # Both objects have the same key, if the values aren't equal, set the value to tbe the output of the diff
        if not @equals a[key], b[key]
          diffs[key] = @diff a[key], b[key]
      else
        # Object a has this key but object b doesn't, remove from a
        diffs[key] = {'o':'-'}
    for own key of b
      if not (key of a) and b[key]?
        # Object b has this key but object a doesn't, add to a
        diffs[key] = {'o':'+', 'v':b[key]}

    return diffs

# This is intended to be used by internal functions to automatically generate
# the correct operations for a value based on the type.
# diff(a,b) returns an operation object, such that when the operation is performed on a, the result is b.
# An operation object is
#
#     {'o':(operation type), 'v':(operation parameter value)}
  diff: (a, b) =>
    if @equals a, b
      return {}
    typea = @typeOf a
    if typea != @typeOf b
      return {'o':'r', 'v':b }

    switch typea
      when 'boolean'  then return {'o': 'r', 'v': b}
      when 'number'   then return {'o': 'r', 'v': b}
      when 'array'    then return {'o': 'L', 'v': @list_diff a, b}
      when 'object'   then return {'o': 'O', 'v': @object_diff a, b}
      when 'string'
        # Use diffmatchpatch here for comparing strings
        diffs = jsondiff.dmp.diff_main a, b
        if diffs.length > 2
          jsondiff.dmp.diff_cleanupEfficiency diffs
        if diffs.length > 0
          return {'o': 'd', 'v': jsondiff.dmp.diff_toDelta diffs}

    return {}


# Applies a diff object (which consists of a map of keys to operations) to an array (`s`) and
# returns a new list with the operations in `diffs` applied to it
  apply_list_diff: (s, diffs) =>
    patched = @deepCopy s
    indexes = []
    deleted = []

    # Sort the keys (which are array indexes) so we can process them in order
    for own key of diffs
      indexes.push key
      indexes.sort()

    for index in indexes
      op = diffs[index]

      # Resulting index may be shifted depending if there were delete
      # operations before the current index.
      shift = (x for x in deleted when x <= index).length
      s_index = index - shift

      switch op['o']
        # Insert new value at index
        when '+'
          patched[s_index..s_index] = op['v']
        # Delete value at index
        when '-'
          patched[s_index..s_index] = []
          deleted[deleted.length] = s_index
        # Replace value at index
        when 'r'
          patched[s_index] = op['v']
        # Integer, add the difference to current value
        when 'I'
          patched[s_index] += op['v']
        # List, apply the diff operations to the current array
        when 'L'
          patched[s_index] = @apply_list_diff patched[s_index], op['v']
        # Object, apply the diff operations to the current object
        when 'O'
          patched[s_index] = @apply_object_diff patched[s_index], op['v']
        # String, apply the patch using diffmatchpatch
        when 'd'
          dmp_diffs = jsondiff.dmp.diff_fromDelta patched[s_index], op['v']
          dmp_patches = jsondiff.dmp.patch_make patched[s_index], dmp_diffs
          dmp_result = jsondiff.dmp.patch_apply dmp_patches, patched[s_index]
          patched[s_index] = dmp_result[0]

    return patched

  apply_list_diff_dmp: (s, delta) =>
      ptext = @_serialize_to_text s

      dmp_diffs = jsondiff.dmp.diff_fromDelta(ptext, delta)
      dmp_patches = jsondiff.dmp.patch_make(ptext, dmp_diffs)
      dmp_result = jsondiff.dmp.patch_apply dmp_patches, ptext

      return @_text_to_array(dmp_result[0])

# Applies a diff object (which consists of a map of keys to operations) to an object (`s`) and
# returns a new object with the operations in `diffs` applied to it
  apply_object_diff: (s, diffs) =>
    patched = @deepCopy s
    for own key, op of diffs
      switch op['o']
        # Add new key/value
        when '+'
          patched[key] = op['v']
        # Delete a key
        when '-'
          delete patched[key]
        # Replace the value for key
        when 'r'
          patched[key] = op['v']
        # Integer, add the difference to current value
        when 'I'
          patched[key] += op['v']
        # List, apply the diff operations to the current array
        when 'L'
          patched[key] = @apply_list_diff patched[key], op['v']
        # Object, apply the diff operations to the current object
        when 'O'
          patched[key] = @apply_object_diff patched[key], op['v']
        # String, apply the patch using diffmatchpatch
        when 'd'
          dmp_diffs = jsondiff.dmp.diff_fromDelta patched[key], op['v']
          dmp_patches = jsondiff.dmp.patch_make patched[key], dmp_diffs
          dmp_result = jsondiff.dmp.patch_apply dmp_patches, patched[key]
          patched[key] = dmp_result[0]

    return patched

# Applies a diff object (which consists of a map of keys to operations) to an object (`s`) and
# returns a new object with the operations in `diffs` applied to it
  apply_object_diff_with_offsets: (s, diffs, field, offsets) =>
    patched = @deepCopy s
    for own key, op of diffs
      switch op['o']
        # Add new key/value
        when '+'
          patched[key] = op['v']
        # Delete a key
        when '-'
          delete patched[key]
        # Replace the value for key
        when 'r'
          patched[key] = op['v']
        # Integer, add the difference to current value
        when 'I'
          patched[key] += op['v']
        # List, apply the diff operations to the current array
        when 'L'
          patched[key] = @apply_list_diff patched[key], op['v']
        # Object, apply the diff operations to the current object
        when 'O'
          patched[key] = @apply_object_diff patched[key], op['v']
        # String, apply the patch using diffmatchpatch
        when 'd'
          dmp_diffs = jsondiff.dmp.diff_fromDelta patched[key], op['v']
          dmp_patches = jsondiff.dmp.patch_make patched[key], dmp_diffs
          if key is field
            patched[key] = @patch_apply_with_offsets dmp_patches, patched[key],
                offsets
          else
            dmp_result = jsondiff.dmp.patch_apply dmp_patches, patched[key]
            patched[key] = dmp_result[0]

    return patched

  transform_list_diff: (ad, bd, s) =>
    console.log("xregular transform_list_diff")
    ad_new = {}
    b_inserts = []
    b_deletes = []
    for own index, op of bd
      index = parseInt(index)
      if op['o'] is '+' then b_inserts.push index
      if op['o'] is '-' then b_deletes.push index
    for own index, op of ad
      index = parseInt(index)
      shift_r = (x for x in b_inserts when x <= index).length
      shift_l = (x for x in b_deletes when x < index).length

      index = index + shift_r - shift_l
      sindex = String(index)

      ad_new[sindex] = op
      if index of bd
        if op['o'] is '+' and bd[index]['o'] is '+'
          continue
        else if op['o'] is '-'
          if bd[index]['o'] is '-'
            delete ad_new[sindex]
        else if bd[index]['o'] is '-'
          if op['o'] is not '+'
            ad_new[sindex] = {'o':'+', 'v': @apply_object_diff s[sindex], op['v'] }
        else
          target_op = {}
          target_op[sindex] = op
          other_op = {}
          other_op[sindex] = bd[index]
          diff = @transform_object_diff(target_op, other_op, s)
          ad_new[sindex] = diff[sindex]
    return ad_new

  transform_list_diff_dmp: (ad, bd, s) =>
    stext = @_serialize_to_text s
    a_patches = jsondiff.dmp.patch_make stext, jsondiff.dmp.diff_fromDelta stext, ad
    b_patches = jsondiff.dmp.patch_make stext, jsondiff.dmp.diff_fromDelta stext, bd

    b_text = (jsondiff.dmp.patch_apply b_patches, stext)[0]
    ab_text = (jsondiff.dmp.patch_apply a_patches, b_text)[0]
    if ab_text != b_text
      dmp_diffs = jsondiff.dmp.diff_lineMode_ b_text, ab_text
      if dmp_diffs.length > 2
        jsondiff.dmp.diff_cleanupEfficiency dmp_diffs
      if dmp_diffs.length > 0
        return jsondiff.dmp.diff_toDelta dmp_diffs
    return ""

  transform_object_diff: (ad, bd, s) =>
#    console.log("transform_object_diff(#{JSON.stringify(ad)}, #{JSON.stringify(bd)}, #{JSON.stringify(s)})");
    ad_new = @deepCopy ad
    for own key, aop of ad
      if not (key of bd) then continue

      sk = s[key]
      bop = bd[key]

      if aop['o'] is '+' and bop['o'] is '+'
        if @equals aop['v'], bop['v']
          delete ad_new[key]
        else
          ad_new[key] = @diff bop['v'], aop['v']
      else if aop['o'] is '-' and bop['o'] is '-'
        delete ad_new[key]
      else if bop['o'] is '-' and aop['o'] in ['O', 'L', 'I', 'd']
        ad_new[key] = {'o':'+'}
        if aop['o'] is 'O'
          ad_new[key]['v'] = @apply_object_diff sk, aop['v']
        else if aop['o'] is 'L'
          ad_new[key]['v'] = @apply_list_diff sk, aop['v']
        else if aop['o'] is 'I'
          ad_new[key]['v'] = sk + aop['v']
        else if aop['o'] is 'd'
          dmp_diffs = jsondiff.dmp.diff_fromDelta sk, aop['v']
          dmp_patches = jsondiff.dmp.patch_make sk, dmp_diffs
          dmp_result = jsondiff.dmp.patch_apply dmp_patches, sk
          ad_new[key]['v'] = dmp_result[0]
        else
          delete ad_new[key]
      else if aop['o'] is 'O' and bop['o'] is 'O'
        ad_new[key] = {'o':'O', 'v': @transform_object_diff aop['v'], bop['v'], sk}
      else if aop['o'] is 'L' and bop['o'] is 'L'
        ad_new[key] = {'o':'L', 'v': @transform_list_diff aop['v'], bop['v'], sk}
      else if aop['o'] is 'd' and bop['o'] is 'd'
        delete ad_new[key]
        a_patches = jsondiff.dmp.patch_make sk, jsondiff.dmp.diff_fromDelta sk, aop['v']
        b_patches = jsondiff.dmp.patch_make sk, jsondiff.dmp.diff_fromDelta sk, bop['v']
        b_text = (jsondiff.dmp.patch_apply b_patches, sk)[0]
        ab_text = (jsondiff.dmp.patch_apply a_patches, b_text)[0]
        if ab_text != b_text
          dmp_diffs = jsondiff.dmp.diff_main b_text, ab_text
          if dmp_diffs.length > 2
            jsondiff.dmp.diff_cleanupEfficiency dmp_diffs
          if dmp_diffs.length > 0
            ad_new[key] = {'o':'d', 'v':jsondiff.dmp.diff_toDelta dmp_diffs}

      return ad_new

  # dummy function here so coffeescript will bind the this variable properly
  # actual function redefined below with original javascript
  patch_apply_with_offsets: (patches, text, offsets) =>
    return

  patch_apply_with_offsets: `function(patches, text, offsets) {
    if (patches.length == 0) {
      return text;
    }

    // Deep copy the patches so that no changes are made to originals.
    patches = jsondiff.dmp.patch_deepCopy(patches);
    var nullPadding = jsondiff.dmp.patch_addPadding(patches);
    text = nullPadding + text + nullPadding;

    jsondiff.dmp.patch_splitMax(patches);
    // delta keeps track of the offset between the expected and actual location
    // of the previous patch.  If there are patches expected at positions 10 and
    // 20, but the first patch was found at 12, delta is 2 and the second patch
    // has an effective expected position of 22.
    var delta = 0;
    for (var x = 0; x < patches.length; x++) {
      var expected_loc = patches[x].start2 + delta;
      var text1 = jsondiff.dmp.diff_text1(patches[x].diffs);
      var start_loc;
      var end_loc = -1;
      if (text1.length > jsondiff.dmp.Match_MaxBits) {
        // patch_splitMax will only provide an oversized pattern in the case of
        // a monster delete.
        start_loc = jsondiff.dmp.match_main(text,
            text1.substring(0, jsondiff.dmp.Match_MaxBits), expected_loc);
        if (start_loc != -1) {
          end_loc = jsondiff.dmp.match_main(text,
              text1.substring(text1.length - jsondiff.dmp.Match_MaxBits),
              expected_loc + text1.length - jsondiff.dmp.Match_MaxBits);
          if (end_loc == -1 || start_loc >= end_loc) {
            // Can't find valid trailing context.  Drop this patch.
            start_loc = -1;
          }
        }
      } else {
        start_loc = jsondiff.dmp.match_main(text, text1, expected_loc);
      }
      if (start_loc == -1) {
        // No match found.  :(
        /*
        if (mobwrite.debug) {
          window.console.warn('Patch failed: ' + patches[x]);
        }
        */
        // Subtract the delta for this failed patch from subsequent patches.
        delta -= patches[x].length2 - patches[x].length1;
      } else {
        // Found a match.  :)
        /*
        if (mobwrite.debug) {
          window.console.info('Patch OK.');
        }
        */
        delta = start_loc - expected_loc;
        var text2;
        if (end_loc == -1) {
          text2 = text.substring(start_loc, start_loc + text1.length);
        } else {
          text2 = text.substring(start_loc, end_loc + jsondiff.dmp.Match_MaxBits);
        }
        // Run a diff to get a framework of equivalent indices.
        var diffs = jsondiff.dmp.diff_main(text1, text2, false);
        if (text1.length > jsondiff.dmp.Match_MaxBits &&
            jsondiff.dmp.diff_levenshtein(diffs) / text1.length >
            jsondiff.dmp.Patch_DeleteThreshold) {
          // The end points match, but the content is unacceptably bad.
          /*
          if (mobwrite.debug) {
            window.console.warn('Patch contents mismatch: ' + patches[x]);
          }
          */
        } else {
          var index1 = 0;
          var index2;
          for (var y = 0; y < patches[x].diffs.length; y++) {
            var mod = patches[x].diffs[y];
            if (mod[0] !== DIFF_EQUAL) {
              index2 = jsondiff.dmp.diff_xIndex(diffs, index1);
            }
            if (mod[0] === DIFF_INSERT) {  // Insertion
              text = text.substring(0, start_loc + index2) + mod[1] +
                     text.substring(start_loc + index2);
              for (var i = 0; i < offsets.length; i++) {
                if (offsets[i] + nullPadding.length > start_loc + index2) {
                  offsets[i] += mod[1].length;
                }
              }
            } else if (mod[0] === DIFF_DELETE) {  // Deletion
              var del_start = start_loc + index2;
              var del_end = start_loc + jsondiff.dmp.diff_xIndex(diffs,
                  index1 + mod[1].length);
              text = text.substring(0, del_start) + text.substring(del_end);
              for (var i = 0; i < offsets.length; i++) {
                if (offsets[i] + nullPadding.length > del_start) {
                  if (offsets[i] + nullPadding.length < del_end) {
                    offsets[i] = del_start - nullPadding.length;
                  } else {
                    offsets[i] -= del_end - del_start;
                  }
                }
              }
            }
            if (mod[0] !== DIFF_DELETE) {
              index1 += mod[1].length;
            }
          }
        }
      }
    }
    // Strip the padding off.
    text = text.substring(nullPadding.length, text.length - nullPadding.length);
    return text;
  }`

window['jsondiff'] = jsondiff
#jsondiff.prototype['entries'] = jsondiff.prototype.entries
#jsondiff.prototype['typeOf'] = jsondiff.prototype.typeOf
#jsondiff.prototype['deepCopy'] = jsondiff.prototype.deepCopy
#jsondiff.prototype['equals'] = jsondiff.prototype.equals
#jsondiff.prototype['diff'] = jsondiff.prototype.diff
#jsondiff.prototype['object_diff'] = jsondiff.prototype.object_diff
#jsondiff.prototype['apply_object_diff'] = jsondiff.prototype.apply_object_diff
#jsondiff.prototype['transform_object_diff'] = jsondiff.prototype.transform_object_diff
