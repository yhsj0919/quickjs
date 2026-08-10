export async function test() {
  const value = Math.trunc(Math.random() * 100).toString();
  const asyncResult = await getDataAsync(
    { count: 5 },
    'from js',
    ['aa', 'bb']
  );
  const nativeResult = await dartMethod({
    count: Math.trunc(Math.random() * 10),
  });

  console.log('registered dart method => ' + nativeResult);
  alert(asyncResult, 'ssss');

  let expectedError;
  try {
    await asyncWithError('{}');
  } catch (error) {
    expectedError = error.message || String(error);
  }

  return {
    expression: value,
    asyncResult,
    nativeResult,
    expectedError,
  };
}

export async function test2(a, b, objectValue, listValue) {
  console.log('test2 arguments', a, b, objectValue, listValue);
  const result = await test();
  console.log('test() result', result);
  return {
    message: 'message from js',
    first: a,
    second: b,
    objectValue,
    listValue,
    nested: result,
  };
}

export async function axiosGet(url) {
  const response = await axios.get(url);
  const text = typeof response.data === 'string'
    ? response.data
    : JSON.stringify(response.data);
  return {
    status: response.status,
    length: text.length,
    preview: text.slice(0, 120),
  };
}

export const flutterJs = {
  key: 'test',
};
